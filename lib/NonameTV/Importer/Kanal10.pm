package NonameTV::Importer::Kanal10;

use strict;
use warnings;

=pod

Channels: Kanal10 (http://kanal10.se/)

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode qw/decode/;
use Data::Dumper;

use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm MonthNumber normUtf8/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  } elsif($file =~ /\.doc$/i) {
    $self->ImportDOC( $file, $chd );
  }


  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "Kanal10: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 2;

  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls

  my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Kanal10: Processing worksheet: $oWkS->{Name}" );

	  my $foundcolumns = 0;

    # browse through rows
    my $i = 1;

    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );

      $date = create_date( ExcelFmt('yyyy-mm-dd', $oWkC->{Val}) );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("Kanal10: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );



      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      $time =~ s/_/:/g; # They fail sometimes


      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      $title =~ s/\((r|p)\)//g if $title;



      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      # Desc (only works on XLS files)
      my $field = "D".$i;
      my $desc = $ref->[1]{$field};
      $ce->{description} = normUtf8($desc) if( $desc );
      $desc = '';

	    progress("Kanal10: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub create_date
{
  my ( $dinfo ) = @_;

  print Dumper($dinfo);

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub extract_episode
{
  my $self = shift;
  my( $ce ) = @_;

  my $d = $ce->{description};
  my $t = $ce->{title};

  # Try to extract episode-information from the description.
  my( $ep, $eps, $ep2, $eps2 );
  my $episode;

  ## description
  if(defined($d)) {
    # Del 2(3)
    ( $ep, $eps ) = ($d =~ /del\s+(\d+)\((\d+)\)/i );
    $episode = sprintf( " . %d/%d . ", $ep-1, $eps )
      if defined $eps;

  	if(defined $episode and defined $eps) {
  		$ce->{description} =~ s/del\s+(\d+)\((\d+)\)//i;
  	}

    # Del 2
    ( $ep ) = ($d =~ /del\s+(\d+)/i );
    $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

    if(defined $episode and defined $ep) {
      $ce->{description} =~ s/Del\s+(\d+)//i;
    }
  }

  ## title
  if(defined($t) and !defined($episode)) {
    # Del 2(3)
    ( $ep, $eps ) = ($t =~ /del\s+(\d+)\((\d+)\)/i );
    $episode = sprintf( " . %d/%d . ", $ep-1, $eps )
      if defined $eps;

  	if(defined $episode and defined $eps) {
  		$ce->{title} =~ s/del\s+(\d+)\((\d+)\)//i;
  	}

    # Del 2
    ( $ep ) = ($t =~ /del\s+(\d+)/i );
    $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

    if(defined $episode and defined $ep) {
      $ce->{title} =~ s/del\s+(\d+)//i;
    }
  }

  if( defined( $episode ) )
  {
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
  }

  $ce->{title} = norm($ce->{title});
  $ce->{description} = norm($ce->{description});
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

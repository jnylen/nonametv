package NonameTV::Importer::Fatstone;

use strict;
use warnings;

=pod
Importer for Fatstone.TV

Channels: Fatstone.TV
Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;


use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;
use Data::Dumper;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/AddCategory norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Fatstone: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";
  my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls
#elsif ( $file =~ /\.xml$/i ){ $oBook = Spreadsheet::ParseExcel::Workbook->Parse($file); progress( "using .xml" );    }   #  staro, za .xls
#print Dumper($oBook);
my $ref = ReadData ($file);

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Fatstone: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			       $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Fatstone: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # time
      $oWkC = $oWkS->{Cells}[$iR][5];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ParseTime($time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      $title =~ s/&quot;/"/ig;

      # desc
      $oWkC = $oWkS->{Cells}[$iR][3];
      next if( ! $oWkC );
      my $desc = $oWkC->Value if( $oWkC->Value );

  	  # extra info
  	  my $genre = norm($oWkS->{Cells}[$iR][4]->{Val}) if $oWkS->{Cells}[$iR][4];

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        description => norm( $desc ),
        start_time => $time,
      };

      # parsing subtitles and ep
      my ($episode, $subtitle);
      if( ( $title, $episode ) = ($ce->{title} =~ /^(.*?) ep (\d+)$/i ) ) {
        $ce->{title} = norm($title);
        $ce->{episode} = sprintf( " . %d . ", $episode-1 );
      } elsif( ( $title, $subtitle ) = ($ce->{title} =~ /^(.*?) - (.*?)$/i ) ) {
        $ce->{title} = norm($title);
        $ce->{subtitle} = norm($subtitle);
      }

      # Genre
      if(defined($genre) and $genre and $genre ne "") {
        my ( $pty, $cat ) = $ds->LookupCat( 'Fatstone', $genre );
      	AddCategory( $ce, $pty, $cat );
      }

      progress("Fatstone: $chd->{xmltvid}: $time - $ce->{title}");

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text = ExcelFmt('yyyy-mm-dd', $text);

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  $text =~ s/ AM\/PM//g; # They fail sometimes
  $text = ExcelFmt('hh:mm', $text);

  my( $hour , $min );

  if( $text =~ /^\d+:\d+/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

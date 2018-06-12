package NonameTV::Importer::VisjonNorge;

use strict;
use warnings;

=pod
Importer for Visjon Norge

Every week is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use Data::Dumper;

use NonameTV qw/norm ParseExcel formattedCell MonthNumber/;
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

  if( $file =~ /\.(xls|xlsx)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "VisjonNorge: Unknown file format: $file" );
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

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "VisjonNorge: $file: Failed to parse excel" );
    return;
  }

  # main foreach
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "VisjonNorge: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 7 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
            $columns{$oWkS->cell($iC, $iR)} = $iC;

			      $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /tittel/ );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /lang tekst/ );

            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /dato/ );
            $columns{'StartTime'} = $iC if( $oWkS->cell($iC, $iR) =~ /start/ ); # Dont set the time to EET
            $columns{'EndTime'} = $iC if( $oWkS->cell($iC, $iR) =~ /slutt/ );

            $columns{'extradesc'} = $iC if( $oWkS->cell($iC, $iR) =~ /kort tekst/ );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /dato/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
      next if( ! $date );

      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			    $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("VisjonNorge: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # time
      my $time = formattedCell($oWkS, $columns{'StartTime'}, $iR);
      next if(!$time);
      $time =~ s/\./:/;
      #if($time eq "24:00") { $time = "00:00"}

      # end time
      my $endtime = formattedCell($oWkS, $columns{'EndTime'}, $iR);
      $endtime =~ s/\./:/;
      #if($endtime eq "24:00") { $endtime = "00:00"}

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);
      next if(!$title);

      # extra info
      my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);
      progress("VisjonNorge: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

      $ce->{end_time} = $endtime if defined $endtime;

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $year, $month );

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+-\S*-\d+$/ ) { # format '01/11/2008'
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S*)-(\d+)$/i );
    $month = MonthNumber( $monthname, 'en' );
  }

  if(!$day) {
    return undef;
  }

  $year += 2000 if( $year < 100 );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

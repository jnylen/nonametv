package NonameTV::Importer::Gospel;

use strict;
use warnings;


=pod

Import data from XLS or XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;

use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm ParseExcel formattedCell MonthNumber AddCategory/;
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

  # Process
  progress( "Gospel: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Gospel: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "Gospel: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;
    my %columns = ();
    my $currdate = "x";

    # Columns
    $columns{'Date'} = 1;
    $columns{'Time'} = 2;
    $columns{'Title'} = 4;
    $columns{'Synopsis'} = 5;
    $columns{'Genre'} = 6;

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      # date
      my $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR), $file);
      next if( ! $date );

      if( $date ne $currdate ){

        progress("Gospel: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);

      # desc
      my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
        description => norm($desc),
      };


	    progress("Gospel: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  #print Dumper($dinfo);

  my( $month, $day, $year, $monthname );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } elsif( $dinfo =~ /^(\d+)-([[:alpha:]]+)-(\d+)$/ ){ # format '11-Jan-2018'
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-([[:alpha:]]+)-(\d+)$/ );
    $month = MonthNumber($monthname, "en");
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

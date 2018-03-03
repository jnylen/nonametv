package NonameTV::Importer::FTV_v2;

use strict;
use warnings;

=pod

Import data for FTV.
Version 2 - Web - Working.

=cut

use utf8;

use DateTime;

use NonameTV qw/norm ParseExcel formattedCell AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "FTV: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Process
  progress( "FTV: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "FTV: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

	  if( $oWkS->{label} !~ /EPG/ ){
      progress( "FTV: $chd->{xmltvid}: Skipping (Not epg): $oWkS->{label}" );
      next;
    }

    my $foundcolumns = 0;
    my %columns = ();
    my $currdate = "x";

    progress( "FTV: Processing worksheet: $oWkS->{label}" );

    # start from row 2
    # Rows
    for(my $iR = 2 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

       # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program/i );
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Date/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Time/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Description/i );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^Date/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # date (column 1)
      my $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR));
      next if( ! $date );

	    if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			    $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("FTV: Date is: $date");
      }

	    # time (column 1)
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);
      next if( ! $time );

      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));

      # Desc
      my $desc = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));

      if( $time and $title ){

        progress("$time $title");

        my $ce = {
          channel_id   => $chd->{id},
		      title		     => $title,
          start_time   => $time,
          description  => $desc,
        };

        $dsh->AddProgramme( $ce );
      }

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );

  # format '2011-05-16'
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );

  # format '03-11-2012'
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d{4})$/i );
  # format '03/11/2012'
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{2}$/i ){
     ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d{2})$/i );
     # format '12-31-13'
  } elsif( $text =~ /^\d{1,2}\/\d{1,2}\/\d{1,2}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{2})$/i );
  }

  $year += 2000 if $year < 100;

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );


	return $dt->ymd("-");
#return $year."-".$month."-".$day;
}

sub ParseTime {
  my( $text ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min, $secs );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+:\d+$/ ){
    ( $hour , $min, $secs ) = ( $text =~ /^(\d+):(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

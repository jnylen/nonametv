package NonameTV::Importer::Matkanalen;

use strict;
use warnings;

=pod

Import data for Nat. Geo. Wild.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
#use Data::Dumper;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "Matkanalen: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Matkanalen: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  my($oWkS, $oWkC);
  my $foundcolumns = 0;

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programtittel/ );
            $columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Tid/ );
            $columns{'Stop'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Slutt/ );
            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Dato/ );
            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Oppsummering/ );
            $columns{'EpisodeTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episodetittel/ );
            $columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Sesongnummer/ );
            $columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episodenummer/ );
            $columns{'Image'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Link til episodebilde/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programtittel/ ); # Only import if season number is found
          }
        }
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
	    $date = ParseDate( $oWkC->Value );
      next if(!$date);

  	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
    		    # save last day if we have it in memory
            #	FlushDayData( $channel_xmltvid, $dsh , @ces );
    			  $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Matkanalen: Date is: $date");
      }

      # time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkC );
      my $start = ParseTime( $oWkC->Value );
      next if( ! $start );

      $oWkC = $oWkS->{Cells}[$iR][$columns{'Stop'}];
      next if( ! $oWkC );
      my $stop = ParseTime( $oWkC->Value );
      next if( ! $stop );

      # program_title (column 4)
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      my $title = norm($oWkC->Value);

      $oWkC = $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
      my $desc = norm($oWkC->Value) if( $oWkC );

      my $ce = {
        channel_id   => $chd->{id},
        title		   => norm($title),
        start_time   => $start,
        end_time => $stop
      };

      ## Episode
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}];
      my $episode = $oWkC->Value if( $oWkC );

      $oWkC = $oWkS->{Cells}[$iR][$columns{'Season'}];
      my $season = $oWkC->Value if( $oWkC );

      if(defined($episode) and $episode ne "" and $episode > 0) {
        $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";
      }

      if(defined($ce->{episode}) and defined($season) and $season > 0) {
        $ce->{episode} = $season-1 . $ce->{episode};
      }

      $oWkC = $oWkS->{Cells}[$iR][$columns{'EpisodeTitle'}];
      my $subtitle = $oWkC->Value if( $oWkC );
      if(defined($subtitle) and $subtitle ne "") {
        $ce->{subtitle} = norm($subtitle);
      }

      $ce->{description} = norm($desc) if defined($desc);

      progress("$start - $title");
      $dsh->AddProgramme( $ce );

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
  if( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{2})$/i );

  # format '2011-05-16'
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );
  }

  if(defined($year)) {
  	$year += 2000 if $year < 100;

	my $dt = DateTime->new(
	    year => $year,
	    month => $month,
	    day => $day,
	    time_zone => "Europe/Oslo"
	);
	return $dt->ymd("-");
  }
}

sub ParseTime {
  my( $text ) = @_;
  my( $hour , $min );

  if( $text =~ /^\d+:\d+/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

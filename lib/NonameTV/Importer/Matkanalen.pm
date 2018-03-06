package NonameTV::Importer::Matkanalen;

use strict;
use warnings;

=pod

Import data for Nat. Geo. Wild.

Features:

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

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xls|xlsx)$/i ){
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
  my $currdate = "x";

  # Process
  progress( "Matkanalen: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Matkanalen: $file: Failed to parse excel" );
    return;
  }


  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "Matkanalen: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;
    my %columns = ();

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Programtittel/ );
            $columns{'Start'} = $iC if( $oWkS->cell($iC, $iR) =~ /Tid/ );
            $columns{'Stop'} = $iC if( $oWkS->cell($iC, $iR) =~ /Slutt/ );
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /Dato/ );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Oppsummering/ );
            $columns{'EpisodeTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episodetittel/ );
            $columns{'Season'} = $iC if( $oWkS->cell($iC, $iR) =~ /Sesongnummer/ );
            $columns{'Episode'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episodenummer/ );
            $columns{'Image'} = $iC if( $oWkS->cell($iC, $iR) =~ /Link til episodebilde/ );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Programtittel/ ); # Only import if season number is found
          }
        }
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date (column 1)
      my $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR), $file);
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
      my $start = ParseTime(formattedCell($oWkS, $columns{'Start'}, $iR));
      next if( ! $start );

      my $stop = ParseTime(formattedCell($oWkS, $columns{'Stop'}, $iR));
      next if( ! $stop );

      # program_title (column 4)
      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));
      my $desc = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));

      my $ce = {
        channel_id   => $chd->{id},
        title		   => norm($title),
        start_time   => $start,
        end_time => $stop
      };

      ## Episode
      my $episode = formattedCell($oWkS, $columns{'Episode'}, $iR);
      my $season = formattedCell($oWkS, $columns{'Season'}, $iR);

      if(defined($episode) and $episode ne "" and $episode > 0) {
        $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";
      }

      if(defined($ce->{episode}) and defined($season) and $season > 0) {
        $ce->{episode} = $season-1 . $ce->{episode};
      }

      my $subtitle = norm(formattedCell($oWkS, $columns{'EpisodeTitle'}, $iR));
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

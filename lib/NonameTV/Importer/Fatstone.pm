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
use Data::Dumper;

use NonameTV qw/AddCategory ParseExcel formattedCell norm MonthNumber/;
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

  # Process
  progress( "Fatstone: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Fatstone: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "Fatstone: $chd->{xmltvid}: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'}    = $iC if( $oWkS->cell($iC, $iR) =~ /^title/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^desc/i );
            $columns{'Genre'}    = $iC if( $oWkS->cell($iC, $iR) =~ /^category/i );
            $columns{'Time'}     = $iC if( $oWkS->cell($iC, $iR) =~ /^start/i );
            $columns{'End'}      = $iC if( $oWkS->cell($iC, $iR) =~ /^stop/i );
            $columns{'Ep No'}    = $iC if( $oWkS->cell($iC, $iR) =~ /^episodeNum/i );
            $columns{'Ses No'}   = $iC if( $oWkS->cell($iC, $iR) =~ /^sesongNum/i );
            $columns{'Year'}     = $iC if( $oWkS->cell($iC, $iR) =~ /^year/i );
            $columns{'Country'}  = $iC if( $oWkS->cell($iC, $iR) =~ /^origin/i );
            $columns{'Date'}  = $iC if( $oWkS->cell($iC, $iR) =~ /^date/i );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^date/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
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
      my $time = ParseTime(formattedCell($oWkS, $columns{'Time'}, $iR));

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);

      # desc
      my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);

  	  # extra info
  	  my $genre = norm(formattedCell($oWkS, $columns{'Genre'}, $iR)) if formattedCell($oWkS, $columns{'Genre'}, $iR);

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        description => norm( $desc ),
        start_time => $time,
      };

      # parsing subtitles and ep
      my ($episode, $season);
      ( $episode ) = (formattedCell($oWkS, $columns{'Ep No'}, $iR) =~ /^ep (\d+)$/i );
      ( $season )  = (formattedCell($oWkS, $columns{'Ses No'}, $iR) =~ /^S\. (\d+)$/i );

      if( defined($season) and $season ne "" and defined($episode) and $episode ne "" ) {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      } elsif( defined($episode) and $episode ne "" ) {
        $ce->{episode} = sprintf( " . %d . ", $episode-1 );
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

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /(.*?) (\d+), (\d+)$/ ) {
    ( $monthname, $day, $year ) = ( $text =~ /, (.*?) (\d+), (\d+)$/ );
    $month = MonthNumber($monthname, "en");
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min, $secs, $ampm );

  if( $text =~ /^\d+:\d+:\d+ (am|pm)/i ){
    ( $hour , $min, $secs, $ampm ) = ( $text =~ /^(\d+):(\d+):(\d+) (AM|PM)/ );
    $hour = ($hour % 12) + (($ampm eq 'AM') ? 0 : 12);
  } elsif($text =~ /^\d+:\d+$/i) {
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  } else {
    print Dumper($text);
  }

  if($hour >= 24) {
    $hour -= 24;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

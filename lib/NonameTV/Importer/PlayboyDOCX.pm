package NonameTV::Importer::PlayboyDOCX;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

Episode numbers parsed from title.
Subtitles.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm MonthNumber DOCXfile2Array/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

# The lowest log-level to store in the batch entry.
# DEBUG = 1
# INFO = 2
# PROGRESS = 3
# ERROR = 4
# FATAL = 5
my $BATCH_LOG_LEVEL = 4;

sub new
{
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
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my @lines = DOCXfile2Array($file);

  # date
  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $line (@lines) {
    # date
    if( isDate( $line ) ) {

      $date = ParseDate( $line );

      if( $date ) {

        progress("PlayboyDOCX: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
          	# save day if we have it in memory
          	# This is done before the last day
  			    FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" );
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $line ) ) {
      my( $time, $title ) = ParseShow( $line );
      next if( ! $time );
      next if( ! $title );

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      # Cleanup
      $ce->{title} =~ s/\(18\+\)$//i;

      $ce->{title} = norm($ce->{title});

      push( @ces , $ce );
    } else {
      my $element = $ces[$#ces];

      if(defined($element->{description}) and $element->{description} ne "" and $line ne "" ) {
        $element->{description} = $line;
      } else {
        $element->{description} .= $line;
      }


    }

  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
  1;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("PlayboyDOCX: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  #


  if( $text =~ /^\d+\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d+)$/i ){ # format 'M�ndag 11st Juli'
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $month, $year, $dummy );

  if( $text =~ /^\d+\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d+)$/i ){ # format '31 MARCH 2016'
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s+(\S+)\s+(\d+)$/i );

    $month = MonthNumber( $monthname, 'en' );
  }

  my $dt = DateTime->new(
  				year => $year,
    			month => $month,
    			day => $day,
      		);

  return $dt->ymd("-");
}

sub isShow {
  my ( $text ) = @_;

  if( $text =~ /^\d+\:\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $desc, $rating );

  ( $time, $title ) = ( $text =~ /^(\d+\:\d+)\s+(.*)$/ );

  my ( $hour , $min ) = ( $time =~ /^(\d+):(\d+)$/ );

  $time = sprintf( "%02d:%02d", $hour, $min );

  return( $time, $title );
}

1;

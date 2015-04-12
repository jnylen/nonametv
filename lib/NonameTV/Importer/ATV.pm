package NonameTV::Importer::ATV;

use strict;
use warnings;

=pod

Imports data from ATV.
The lists is in XML format. Every day is handled as a seperate batch.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;

use NonameTV qw/norm ParseXml AddCategory MonthNumber/;
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

  # use augment
  $self->{datastore}->{augment} = 1;

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

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "ATV: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "ATV: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//TRANSMISSION_SCHEDULE" );

  if( $rows->size() == 0 ) {
    error( "ATV: $chd->{xmltvid}: No Days found" ) ;
    return;
  }

  # Days
  foreach my $row ($rows->get_nodelist)
  {
    my $date = ParseDate($row->findvalue( 'TXDAY_DATE' ));

    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
        $dsh->EndBatch( 1 );
      }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("ATV: Date is: $date");
    }


    # programs
    my $programs = $row->findnodes( ".//TRANSMISSION_SLOT" );
    foreach my $program ($programs->get_nodelist)
    {
      my $time      = $program->findvalue( './/START_TIME' );
      my $title     = norm($program->findvalue( './/GERMAN_TITLE' ));
      my $title_org = norm($program->findvalue( './/ORIGINAL_TITLE' ));

      my $subtitle = $program->findvalue( './/EPTITLE' );
      my $episode  = $program->findvalue( './/EPISODENR' );
      my $season   = $program->findvalue( './/SEASON' );
      my $episodes = $program->findvalue( './/EPISODES' );

      my $year     = $program->findvalue( './/PRODYEAR' );
      my $country  = $program->findvalue( './/COUNTRIES' );
      my $genre    = $program->findvalue( './/GENRE' );
      my $audio    = $program->findvalue( './/AUDIOFORMAT' );

      my $desc     = $program->findvalue( './/SYNOPSIS' );
      my $director = $program->findvalue( './/DIRECTOR' );
      my $actors   = $program->findvalue( './/CAST' );

      next if $title eq "";

      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $time,
        description => norm($desc),
      };

      $ce->{subtitle} = norm($subtitle) if $subtitle;

      if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      # Episode info in xmltv-format
      if( ($episode ne "") and ( $episodes ne "") and ( $season ne "") and ($season > 0) )
      {
        $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $episodes );
      }
      elsif( ($episode ne "") and ( $season ne "") and ($season > 0) )
      {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      }
      elsif( ($episode ne "") and ( $episodes ne "") )
      {
        $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $episodes );
      }
      elsif( $episode ne "" )
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

      # Org. Title
      if(defined($title_org) and $title_org ne "") {
        if(defined($season) and $season ne "") {
            my $season_no_zero = $season;
            $season_no_zero+=0;

            $title_org =~ s/$season$//;
            $title_org =~ s/$season_no_zero$//;
        }

        $ce->{original_title} = norm($title_org) if norm($title) ne norm($title_org);
      }

      # Genre
      if( defined($genre) and $genre ne "" ){
        my ( $program_type, $category ) = $self->{datastore}->LookupCat( "ATV", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      # Directors
      if(defined($director) and $director ne "") {
        $ce->{directors} = join ";", split(", ", $director);
        $ce->{program_type} = "movie";
      }

      # Actors
      if(defined($actors) and $actors ne "") {
        $ce->{actors} = join ";", split(", ", $actors);
      }

      $ce->{stereo} = lc($audio);

      progress( "ATV: $chd->{xmltvid}: $time - $title" );
      $dsh->AddProgramme( $ce );
    }

  } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text, $year ) = @_;
  my( $dayname, $day, $monthname, $month );

  # format 'Måndag 11 06'
  ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s+(\S+)\s+(\d+)$/i );
  $month = MonthNumber( $monthname, 'de' );

  #print("day: $day, month: $month, year: $year\n");

  my $dt = DateTime->new(
  				year => $year,
    			month => $month,
    			day => $day,
      		);
  return $dt->ymd("-");
}

1;
package NonameTV::Importer::HorseAndCountry;

use strict;
use warnings;

=pod

Imports data from H&C.
The lists is in XML format. Every day is handled as a seperate batch.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;

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

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "HaC: $chd->{xmltvid}: Processing XML $file" );

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns="urn:tva:metadata:2004"||;
  $cref =~ s| xmlns='urn:tva:metadata:2004'||;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if( not defined( $doc ) ) {
    error( "HaC: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;
  my %programs;

  # the grabber_data should point exactly to one worksheet
  my $pis = $doc->findnodes( ".//ProgramInformation" );

  if( $pis->size() == 0 ) {
      error( "HaC: No ProgramInformation found" ) ;
      return;
  }

  foreach my $pi ($pis->get_nodelist) {
    my $pid = $pi->findvalue( './@programId' );

    my $p = {
      title          => norm($pi->findvalue( './/BasicDescription//Title[1]' )),
      subtitle       => norm($pi->findvalue( './/BasicDescription//Title[2]' )),
      episode_number => norm($pi->findvalue( './/BasicDescription//EpisodeNumber' )),
      synopsis       => norm($pi->findvalue( './/BasicDescription//Synopsis' )),
      season_number  => norm($pi->findvalue( './/BasicDescription//SeasonNumber' )),
      prod_year      => norm($pi->findvalue( './/BasicDescription//ReleaseInformation/ReleaseDate/Year' ))
    };

    $programs{$pid} = $p;

  }

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//ScheduleEvent" );

  if( $rows->size() == 0 ) {
      error( "HaC: No Rows found" ) ;
      return;
  }

  # Batch id
  my ($year, $month, $day) = ($file =~ /(\d\d\d\d)(\d\d)(\d\d)/);
  my $batchid = $chd->{xmltvid} . "_" . $year . "-" . $month . "-" . $day;
  $dsh->StartBatch( $batchid );

  foreach my $row ($rows->get_nodelist) {
    my $program_id = $row->findvalue( './/Program/@crid' );
    my $start      = ParseDateTime($row->findvalue( './/PublishedStartTime' ));
    my $date       = $start->ymd("-");

    my $pd         = $programs{$program_id};
    my $title      = $pd->{title};
    my $desc       = $pd->{synopsis};
    my $subtitle   = $pd->{subtitle};
    my $year       = $pd->{prod_year};
    my $episode    = $pd->{episode_number};
    my $season     = $pd->{season_number};
    $desc =~ s/\((.*?)\)$//;

    ## Batch
  	if($date ne $currdate ) {
  		#$dsh->StartDate( $date, "00:00" );
  		$currdate = $date;

  		progress("HaC: Date is: $date");
  	}

    my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->ymd("-") . " " . $start->hms(":"),
        description => norm($desc),
    };

    # Season
    if(defined($episode) and $episode ne "" and defined($season) and $season ne "") {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif(defined($episode) and $episode ne "") {
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    # Subtitle
    $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "" and $subtitle ne $title;

    # Year
  	if( defined( $year ) and ($year =~ /(\d\d\d\d)/) ) {
  		$ce->{production_date} = "$1-01-01";
  	}

    progress( "HaC: $start - ".norm($ce->{title}) );
    $ds->AddProgramme( $ce );
  }

  $ds->EndBatch( 1 );

}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "Europe/Stockholm"
  );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

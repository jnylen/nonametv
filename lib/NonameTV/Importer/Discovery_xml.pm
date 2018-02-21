package NonameTV::Importer::Discovery_xml;

use strict;
use warnings;

=pod

Import data for DiscoveryChannel in xml-format.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}


sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};

  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//BROADCAST" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  foreach my $b ($ns->get_nodelist) {
    # Verify that there is only one PROGRAMME
    # Verify that there is only one TEXT.

    my $start = $b->findvalue( "BROADCAST_START_DATETIME" );
    my $end = $b->findvalue( "BROADCAST_END_TIME" );
    my $title_lang = $b->findvalue( "BROADCAST_TITLE" );
    my $title_org = $b->findvalue( "PROGRAMME[1]/PROGRAMME_TITLE_ORIGINAL" );
    my $title = $title_lang || $title_org;

    my $subtitle_lang = $b->findvalue( "BROADCAST_SUBTITLE" );
    my $subtitle_org = $b->findvalue( "PROGRAMME[1]/PROGRAMME_SUBTITLE_ORIGINAL" );
    my $season = $b->findvalue( "PROGRAMME[1]/SERIES_NUMBER" );
    my $episode = $b->findvalue( "PROGRAMME[1]/EPISODE_NUMBER" );
    my $desc = $b->findvalue( "PROGRAMME[1]/TEXT[1]/TEXT_TEXT" );
    my $year = $b->findvalue( "PROGRAMME[1]/PROGRAMME_YEAR" );
    my $rerun = $b->findvalue( 'BROADCAST_INFO/@RERUN' );
    my $is_hd = $b->findvalue( 'BROADCAST_INFO/@HD' );
    my $live = $b->findvalue( 'BROADCAST_INFO/@LIVE' );

    my $ce = {
      channel_id => $chd->{id},
      start_time => ParseDateTime( $start, $chd->{grabber_info} ),
      end_time => ParseDateTime( $end, $chd->{grabber_info} ),
      title => norm($title),
      description => norm($desc),
    };

    $ce->{subtitle} = norm($subtitle_lang) if $subtitle_lang ne "";
    $ce->{original_subtitle} = norm($subtitle_org) if $subtitle_org ne "" and $subtitle_org ne $subtitle_lang;
    $ce->{original_title} = norm($title_org) if $ce->{title} ne $title_org and $title_org ne "";

    if( $episode and $episode ne "" ){
      if( ($episode > 0) and ($season ne "" and $season > 0) )
      {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      }
      elsif( $episode > 0 )
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }
    }

    # year
    if(defined($year) and $year =~ /\((\d\d\d\d)\)/) {
      $ce->{production_date} = "$1-01-01";
    }

    my $extra = {};
    $extra->{qualifiers} = [];

    # HD?
    if( defined($is_hd) and $is_hd eq "Yes" )
	  {
	    $ce->{quality} = "HDTV";
      push @{$extra->{qualifiers}}, "HD";
	  } elsif( defined($is_hd) and $is_hd eq "No" ) {
      push @{$extra->{qualifiers}}, "SD";
    }

    # Find live-info
  	if( $live eq "Yes" )
  	{
  	  $ce->{live} = "1";
      push @{$extra->{qualifiers}}, "live";
  	}
    else
    {
      $ce->{live} = "0";
    }

    p($start." $ce->{title}");

    $ce->{extra} = $extra;

    $ds->AddProgramme( $ce );
  }

  return 1;
}

# The start and end-times are in the format 2007-12-31T01:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str, $grabber_info ) = @_;

  my( $year, $month, $day, $hour, $minute ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)$/ );

  # Select grabber info
  my $timezone = "Europe/Stockholm";
  if($grabber_info =~ /UTC/i) {
    $timezone = "UTC";
  }

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    time_zone => $timezone
  );

  $dt->set_time_zone( "UTC" );

  return $dt->ymd("-") . " " . $dt->hms(":");
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = sprintf( "%s%s", $self->{UrlRoot}, $chd->{grabber_info} );

  return( $url, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

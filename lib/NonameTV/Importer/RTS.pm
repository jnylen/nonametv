package NonameTV::Importer::RTS;

=pod


=cut

use strict;
use warnings;

use DateTime;
use Data::Dumper;
use JSON -support_by_pp;
use POSIX 'strftime';

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress w error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $dsh->{DETECT_SEGMENTS} = 1;
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = 'https://api.programmes.rts.ch/api/schedules/day/' . $date
    . '?channel=' . $chd->{grabber_info};

  return( $url, undef );
}

sub ContentExtension {
  return 'json';
}

sub FilteredExtension {
  return 'json';
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Date
  my( $date ) = ($batch_id =~ /_(.*)/);
  $dsh->StartDate( $date , "00:00" );

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref)->{"schedules"}->[0]->{'broadcasts'};

  foreach my $p (@{$data}) {
    my $title = $p->{"titles"}->[0];
    my $subtitle = $p->{"titles"}->[1];
    my $subtitle_org = $p->{"titles"}->[2];

    # Time
    my $start    = $self->create_dt($p->{"plannedBroadcastingStartTime"});
    my $stop     = $self->create_dt($p->{"plannedBroadcastingEndTime"});
    my $how_long = $start->delta_ms($stop)->in_units('minutes');

    my $desc = $p->{"description"};

    # Episode
    my $episode = $p->{"episode"}->{'number'};
    my $season  = $p->{"episode"}->{'season'};

    # Other
    my $video = $p->{"videoStatus"};
    my $audio = $p->{"audioStatus"};
    my $live  = $p->{"live"};
    my $rerun = $p->{"rerun"};
    my $prodyear = $p->{"production"}->{'year'};
    #my $prodcountry = $p->{"production"}->{'country'}->[0]->{'code'};
    my $genres = $p->{'genres'}->[0];

    # Time
    my $time = $start->hms(":");

    # Put everything in a array
    my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
        description => norm($desc)
    };

    # Extra
    my $extra = {};
    $extra->{descriptions} = [];
    $extra->{qualifiers} = [];
    $extra->{images} = [];

    # Subtitle
    $ce->{subtitle} = norm($subtitle) if defined($subtitle);
    $ce->{original_subtitle} = norm($subtitle_org) if defined($subtitle_org);

    # Episode
    if(defined($episode) and defined($season)) {
      $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
    } elsif(defined($episode)) {
      $ce->{episode} = '. ' . ($episode - 1) . ' .';
    }

    # Audio and video
    if(defined($video) and $video eq "16:9") {
      $ce->{aspect} = "16:9";
    } elsif(defined($video) and $video eq "4:3") {
      $ce->{aspect} = "4:3";
    }

    if(defined($audio) and $audio eq "Surround") {
      $ce->{stereo} = "surround";
    } elsif(defined($audio) and $audio eq "Stereo") {
      $ce->{stereo} = "stereo";
    } elsif(defined($audio) and $audio eq "Bicanal") {
    #  $ce->{stereo} = "bilingual";
    }


    # Live?
    if( defined($live) and $live eq "true" ) {
      $ce->{live} = 1;
      push @{$extra->{qualifiers}}, "live";
    } else {
      $ce->{live} = 0;
    }



    # Credits
    my @actors;
    my @directors;
    my $name;

    my $actors = $p->{"credits"}->{'actors'};
    foreach my $act (@{$actors})
    {
      $name = norm($act->{'name'});
      push @actors, $name;
    }

    my $directors = $p->{"credits"}->{'directors'};
    foreach my $dir (@{$directors})
    {
      $name = norm($dir->{'name'});
      push @directors, $name;
    }

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ";", @directors;
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ";", @actors;
    }

    if( defined($prodyear) and $prodyear =~ /(\d\d\d\d)/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # title for movies
    if(($ce->{title} =~ /^Film/ or $ce->{title} =~ /^Box office/) and scalar( @directors ) > 0) {
      $ce->{title} = $ce->{subtitle};
      $ce->{subtitle} = undef;
      $ce->{program_type} = "movie";
    } elsif($how_long > 75 and scalar( @directors ) > 0) {
      $ce->{program_type} = "movie";
    }

    # Genres
    if(defined($genres) and $genres) {
        my ( $pty, $cat ) = $ds->LookupCat( 'RTS', $genres );
        AddCategory( $ce, $pty, $cat );
    }

    # Images
    my $images = $p->{'images'};
    foreach my $img (@{$images})
    {
      if(defined($img->{'urlImage'}) and $img->{'urlImage'} ne "") {
        push @{$extra->{images}}, { url => $img->{'urlImage'}, source => "RTS" };
      }
    }

    $ce->{extra} = $extra;

    progress($start." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub create_dt ( $ )
{
  my $self = shift;
  my ($timestamp) = @_;

  $timestamp =~ s/000$//; # Wrong.
  my $datetime = strftime("%Y-%m-%dT%H:%M:%S",localtime($timestamp));

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second) = ($datetime =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
    if( !defined( $year )|| !defined( $hour ) || ($month < 1) ){
      w( "could not parse timestamp: $timestamp" );
      return undef;
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => 'Europe/Zurich'
    );
    #$dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;

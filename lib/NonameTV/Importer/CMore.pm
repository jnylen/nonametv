package NonameTV::Importer::CMore;

use strict;
use warnings;

=pod

Importer for data from C More.
One file per channel and day downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Try::Tiny;

use Compress::Zlib;

use NonameTV qw/ParseXml norm AddCategory AddCountry FixSubtitle/;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

    # Canal Plus' webserver returns the following date in some headers:
    # Fri, 31-Dec-9999 23:59:59 GMT
    # This makes Time::Local::timegm and timelocal print an error-message
    # when they are called from HTTP::Date::str2time.
    # Therefore, I have included HTTP::Date and modified it slightly.

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

#  my $url = 'http://press.cmore.se/export/xml/' . $date . '/' . $date . '/?channelId=' . $chd->{grabber_info};
  my $url = $self->{UrlRoot} . 'export/xml/' . $date . '/' . $date . '?channelId=' . $chd->{grabber_info};

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $uncompressed = Compress::Zlib::memGunzip($$cref);
  my $doc;

  if( defined $uncompressed ) {
      $doc = ParseXml( \$uncompressed );
  }
  else {
      $doc = ParseXml( $cref );
  }

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Channel" );

  if( $ns->size() == 0 ) {
    return (undef, "No channels found" );
  }

#  foreach my $ch ($ns->get_nodelist) {
#   my $currid = $ch->findvalue( '@Id' );
#    if( $currid != $chid ) {
#      $ch->unbindNode();
#    }
#  }

  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Schedule" );

  if( $ns->size() == 0 )
  {
    f "No data found";
    return 0;
  }

  foreach my $sc ($ns->get_nodelist)
  {
    # Sanity check.
    # What does it mean if there are several programs?
    if( $sc->findvalue( 'count(.//Program)' ) != 1 ) {
      f "Wrong number of Programs for Schedule " . $sc->findvalue( '@Id' );
      return 0;
    }

    my $title = $sc->findvalue( './Program/@Title' );

    my $start;

    try {
      $start = $self->create_dt( $sc->findvalue( './@CalendarDate' ) );
    } catch { print("error: $_\n"); next; };

    if(!defined($start) )
    {
      w "Invalid starttime '" . $sc->findvalue( './@CalendarDate' ) . "'. Skipping.";
      next;
    }

    my $series_title = $sc->findvalue( './Program/@SeriesTitle' );
    my $org_title = $sc->findvalue( './Program/@Title' );

    my $firstcd = norm($sc->findvalue( './Program/@FirstCalendarDate' ));

    my $bline = $sc->findvalue( './Program/Synopsis/ExtraShort' );
    my $org_desc = $sc->findvalue( './Program/Synopsis/Short' );
    my $med_desc = $sc->findvalue( './Program/Synopsis/Medium' );
    my $epi_desc = $sc->findvalue( './Program/Synopsis/Long' );
    my $desc  = $med_desc || $epi_desc || $org_desc;

    my $genre = norm($sc->findvalue( './Program/@GenreKey' ));

    # Premiere? Live?
    my $premiere = $sc->findvalue( './@IsPremiere' );
    my $type     = $sc->findvalue( './@Type' );
    my $dubbed   = $sc->findvalue( './@IsDubbed' );

    # program_type can be partially derived from this:
    my $class = $sc->findvalue( './Program/@Class' );
    my $cate = $sc->findvalue( './Program/@Category' );

    my $production_year = $sc->findvalue( './Program/@ProductionYear' );
    my $production_country = $sc->findvalue( './Program/@ProductionCountry' );


    # Episode info
    my $epino = $sc->findvalue( './Program/@EpisodeNumber' );
    my $seano = $sc->findvalue( './Program/@SeasonNumber' );
    my $of_episode = $sc->findvalue( './Program/@NumberOfEpisodes' );

    # Actors and Directors
    my $actors = norm( $sc->findvalue( './Program/@Actors' ) );
    my $direcs = norm( $sc->findvalue( './Program/@Directors' ) );

    # ids
    my $assetid  = $sc->findvalue( './@PlayAssetId1' );
    my $seriesid = $sc->findvalue( './Program/@SeriesId' );
    my $vod      = $sc->findvalue( './Program/@Vod' );
    my $vodstart = $sc->findvalue( './Program/@VodStart' );
    my $vodend   = $sc->findvalue( './Program/@VodEnd' );

    # Ratings
    # GREEN = Barntillåten, Turqoise = Från 7 år, Blue = Från 11 år, Orange = Från 15 år
    my $age_rating = $sc->findvalue( './Program/@Rating' );

    my $ce = {
      channel_id  => $chd->{id},
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
    };

    # Extra
    my $extra = {};
    $extra->{descriptions} = [];
    $extra->{qualifiers} = [];
    $extra->{images} = [];
    $extra->{sport} = {};

    # descriptions
    if($bline and defined($bline) and norm($bline) ne "") {
      push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($bline), type => "bline" };
    }
    if($epi_desc and defined($epi_desc) and norm($epi_desc) ne "") {
      my $seriesdesc = $epi_desc;
      #$seriesdesc =~ s/$med_desc//i;

      # Season / series
      if($seriesdesc =~ /(säsong|sæson|kausi|sesong)/i) {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($seriesdesc), type => "season" };
      } else {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($seriesdesc), type => "series" };
      }

    }
    if($med_desc and defined($med_desc) and norm($med_desc) ne "") {
      push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($med_desc), type => "episode" };
    }

    # Movie got another way of external id
    if($cate eq 'Film') {
      $extra->{external} = {type => "cmore_movie", id => $assetid};
    } elsif($class eq "Sport" && $cate eq 'Game') {
      $extra->{external} = {type => "cmore_sport", id => $assetid};
    } elsif($type eq 'EpisodeProgram') {
      $extra->{external} = {type => "cmore_series", id => $seriesid};
    }

    # Sport event stuff
    if($class eq "Sport" && $cate eq 'Game') {
      # Ice hockey, soccer etc (team specific)
      #$extra->{sports} = {teams => [], event => undef, location => undef, type => undef};

    } elsif($class eq "Sport" && $cate eq 'Event') {
      # Golf
      # SHL Awards (prisceromoni)
    }

    # Series stuff
    if( $series_title =~ /\S/ )
    {
      $ce->{title} = norm($series_title);
      $title = norm( $title );

      if( $title =~ /^Del\s+(\d+),\s+(.*)/ )
      {
        $ce->{subtitle} = $2;
      }
      elsif( $title ne $ce->{title} )
      {
        $ce->{subtitle } = $title;
      }
    }
    else
    {
	    # Remove everything inside ()
	    $org_title =~ s/\(.*\)//g;
      $ce->{title} = norm($org_title) || norm($title);
    }

    # Categories and genres
    my($program_type, $category ) = $ds->LookupCat( "CMore_genre", $genre );
    AddCategory( $ce, $program_type, $category );
    my($program_type2, $category2 ) = $ds->LookupCat( "CMore_category", $cate );
    AddCategory( $ce, $program_type2, $category2 );
    my($country ) = $ds->LookupCountry( "CMore", $production_country );
    AddCountry( $ce, $country );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    # Episodes
    if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
          if($of_episode) {
          	$ce->{episode} = sprintf( "%d . %d/%d .", $seano-1, $epino-1, $of_episode );
          }
     	}else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
          if( defined( $production_year ) and
            ($production_year =~ /\d{4}/) )
        	{
        	    my( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
          		$ce->{episode } = $year-1 . " " . $ce->{episode};
        	}
        }

        $ce->{program_type} = 'series';
    }

    # Actors and directors
    if(defined($actors)) {
    	$ce->{actors} = parse_person_list($actors);
    }

    if(defined($direcs)) {
    	$ce->{directors} = parse_person_list($direcs);
    }

    #$self->extract_extra_info( $ce );

    # Program types
    if($cate eq 'Film') {
        $ce->{program_type} = 'movie';
    } elsif($class eq "Sport" && $cate eq 'Game') {
        $ce->{program_type} = 'sports';
        $ce->{episode} = undef;
    } else {
        $ce->{program_type} = 'series';
    }

    # Org title
    my $title_org = $sc->findvalue( './Program/@OriginalTitle' );
    if($ce->{program_type} eq 'series') {
        $ce->{subtitle} = norm($title_org);
    } elsif($ce->{program_type} eq 'movie') {
        $ce->{original_title} = norm(FixSubtitle(norm($title_org))) if $ce->{title} ne $title_org and norm($title_org) ne "";
    }

    p( "CMore: $chd->{xmltvid}: $start - $title" );

    # No sports image as CMore told us we can't include those
    if($class ne "Sport" && $cate ne 'Game')
    {
      # Find all "Schedule"-entries.
      my $images = $sc->find( "./Program/Resources/Image" );

      # Each
      foreach my $ic ($images->get_nodelist)
      {
        # Cover / Poster
        if($ic->findvalue( './@Category' ) eq 'Cover') {
          push @{$extra->{images}}, { url => 'https://img-cdn-cmore.b17g.services/' . $ic->findvalue( './@Id' ) . '/8.img', type => 'cover', title => undef, copyright => undef, source => "CMore" };
        } elsif($ic->findvalue( './@Category' ) eq 'Primary') {
          if($cate eq "Film") {
            push @{$extra->{images}}, { url => 'https://img-cdn-cmore.b17g.services/' . $ic->findvalue( './@Id' ) . '/8.img', type => 'landscape', title => undef, copyright => undef, source => "CMore" };
          } else {
            push @{$extra->{images}}, { url => 'https://img-cdn-cmore.b17g.services/' . $ic->findvalue( './@Id' ) . '/8.img', type => 'episode', title => undef, copyright => undef, source => "CMore" };
          }
        }
      }
    }

    # Live?
    if($type eq "Live") {
      $ce->{live} = 1;
      push @{$extra->{qualifiers}}, "live";
    } else {
      $ce->{live} = 0;
    }

    # Premiere
    if($premiere eq "true") {
      $ce->{new} = 1;
      push @{$extra->{qualifiers}}, "new";
    } else {
      $ce->{new} = 0;
      push @{$extra->{qualifiers}}, "repeat";
    }

    # Dubbed?
    if($dubbed eq "true") {
      push @{$extra->{qualifiers}}, "dubbed";
    }

    # VOD?
    if($vod eq "true") {
      push @{$extra->{qualifiers}}, "catchup";
    }

    # Sports data
    if(defined($cate) and $cate eq "Game") {
      my($league3, $game3 ) = $ds->LookupLeague( "CMore_league", $series_title );

      if(defined($league3)) {
        $extra->{sport}->{league} = $league3;
        @{$extra->{sport}->{teams}}  = split(" - ", $title_org);
        $extra->{sport}->{game}   = lc($game3);

        # Air date
        if( defined( $firstcd ) and ($firstcd =~ /(\d\d\d\d)-(\d\d)-(\d\d)/) )
        {
          $extra->{sport}->{date} = "$1-$2-$3";
        }

        # Round
        if(defined($org_desc) and ($org_desc =~ /Omg.ng (\d+)/)) {
          $extra->{sport}->{round} = $1;
        }
      }
    }

    $ce->{extra} = $extra;

    $ds->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );

  if( $second > 59 ) {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;

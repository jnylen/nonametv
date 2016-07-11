package NonameTV::Importer::Clipsource;

use strict;
use warnings;

=pod

Importer for data from Clipsource
Channels: Kanal 5, Kanal 9, Kanal 11

Features:

=cut

use DateTime;
use XML::LibXML;
use XML::LibXML::XPathContext;
use IO::Uncompress::Unzip qw/unzip/;
use Data::Dumper;
use Encode qw/encode decode/;

use NonameTV qw/ParseXml norm AddCountry AddCategory FixSubtitle/;
use NonameTV::Log qw/progress error/;

use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{ApiKey} ) or die "You must specify ApiKey";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  # Clean
  $self->{SILENCE_DUPLICATE_SKIP} = 1;

  return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( \$cref );

  if( not defined $doc ) {
    return (undef, "Parse2Xml failed" );
  }

  # events includes rerun, live, start, end and catchup, prev aired
  my $eis = $doc->findnodes( ".//event" );
  my %events;

  if( $eis->size() == 0 ) {
      error( "Clipsource: No Events found" ) ;
      return;
  }

  my $i = 0;
  foreach my $ei ($eis->get_nodelist) {
    my $eid = $ei->findvalue( 'contentIdRef' );

    my $e = {
      startTime       => norm($ei->findvalue( 'timeList/startTime' )),
      endTime         => norm($ei->findvalue( 'timeList/endTime' )),
      live            => norm($ei->findvalue( 'live' )),
      rerun           => norm($ei->findvalue( 'rerun' )),
      materialIdRef   => norm($ei->findvalue( 'materialIdRef' ))
    };

    #print Dumper($e);

    $events{$i} = $e;
    $i++;
  }

  # materials include aspect ratio and audio etc.
  my $mis = $doc->findnodes( ".//material" );
  my %materials;

  if( $mis->size() == 0 ) {
      error( "Clipsource: No Materials found" ) ;
      return;
  }

  foreach my $mi ($mis->get_nodelist) {
    my $mid = $mi->findvalue( 'contentIdRef' );

    my $m = {
      aspectRatio     => norm($mi->findvalue( 'aspectRatio' )),
      videoFormat     => norm($mi->findvalue( 'videoFormat' )),
      audio_lang      => norm($mi->findvalue( 'audioList/format/@language' )),
      audio_format    => norm($mi->findvalue( 'audioList/format' )),
      catchup         => 0,
      startover       => 0
    };

    # Rights
    my $rights       = $mi->findnodes( 'rightsCategoryList/rightsCategory' );
    foreach my $right ($rights->get_nodelist)
    {
       # devicetypes
       foreach my $device ($right->findnodes( 'deviceTypeList/deviceType' )->get_nodelist)
       {
         # STB?
         if($device->to_literal eq "stb" and ($right->findvalue( 'catchUpRights/@fastForward' ) eq "true" or $right->findvalue( 'catchUpRights/@rewind' ) eq "true" or $right->findvalue( 'catchUpRights/@pause' ) eq "true")) {
           $m->{catchup} = 1;
         }
         if($device->to_literal eq "stb" and ($right->findvalue( 'startOverRights/@fastForward' ) eq "true" or $right->findvalue( 'startOverRights/@rewind' ) eq "true" or $right->findvalue( 'startOverRights/@pause' ) eq "true")) {
           $m->{startover} = 1;
         }
       }
    }

    $materials{$mid} = $m;
  }


  # programmes
  my $xpc = XML::LibXML::XPathContext->new( );
  my $rows = $xpc->findnodes( './/content', $doc );

  if( $rows->size() == 0 ) {
      error( "Clipsource: No Rows found" ) ;
      return;
  }

  # Start date
  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date , "00:00" );
  my @ces;

  my $i2 = 0;
  foreach my $row ($rows->get_nodelist) {
    $xpc->setContextNode( $row );
    my $cid = norm($xpc->findvalue( 'contentId' ));

    # event
    my $ed         = $events{$i2};
    my $start      = ParseDateTime($ed->{startTime});
    my $end        = ParseDateTime($ed->{endTime});

    my $live       = $ed->{live};
    my $rerun      = $ed->{rerun};

    # material
    my $md         = $materials{$cid};
    my $aspect     = $md->{aspectRatio};
    my $audio_lang = $md->{audio_lang};
    my $a_format   = $md->{audio_format};
    my $v_format   = $md->{videoFormat};

    # content
    my $desc   = $xpc->findvalue( 'descriptionList/description[@type="content"]' );

    my $title        = $xpc->findvalue( 'genericTitleList/title' );
    my $titles       = $xpc->findnodes( 'titleList/title' );

    # extra
    my $season       = $xpc->findvalue( 'seasonNumber' );
    my $episode      = $xpc->findvalue( 'episodeNumber' );
    my $prodyear     = $xpc->findvalue( 'productionYear' );

    my $ce = {
        channel_id   => $chd->{id},
        title        => norm($title),
        start_time   => $start->hms(":"),
        description  => norm($desc),
    };

    # extra
    my $extra = {};
    $extra->{titles} = [];
    $extra->{descriptions} = [];
    $extra->{qualifiers} = [];

    # Season and episode
    if($season and $episode) {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif($episode) {
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    # Prodyear
    if( $prodyear =~ /(\d\d\d\d)/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # Org title
    foreach my $titles2 ($titles->get_nodelist)
    {
      my $titler = $titles2->to_literal;

      # original?
      if($titles2->findvalue('./@original') eq "true" and $titles2->findvalue( './@language' ) eq "eng" and defined($titler) and $titler ne "") {
        $ce->{original_title} = FixSubtitle(norm($titler)) if norm($titler) ne norm($title);
      }
    }

    # Categories
    my $cats  = $xpc->findnodes( 'categoryList/category/treeNode' );
    foreach my $cat ($cats->get_nodelist) {
      if($cat->findvalue('treeNode') eq "Serier") {
        $ce->{program_type} = "series";
      } elsif($cat->findvalue('treeNode') eq "Film") {
        $ce->{program_type} = "movie";
      } elsif($cat->findvalue('treeNode') eq "Sport") {
        $ce->{program_type} = "sports";
      }
    }

    # Genres
    my $genres  = $xpc->findnodes( 'genreList/genre' );
    foreach my $genre ($genres->get_nodelist) {
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Clipsource", $genre->to_literal );
      AddCategory( $ce, $program_type, $category );
    }

    # Rerun?
    if($rerun eq "true") {
      $ce->{new} = "0";
      push $extra->{qualifiers}, "repeat";
    } else {
      $ce->{new} = "1";
      push $extra->{qualifiers}, "new";
    }

    # Live?
    if($live eq "true") {
      $ce->{live} = "1";
      push $extra->{qualifiers}, "live";
    } else {
      $ce->{live} = "0";
    }

    # Audio?
    if(defined($a_format) and $a_format eq "mono") {
      $ce->{stereo} = "mono";
      push $extra->{qualifiers}, "mono";
    } elsif(defined($a_format) and $a_format eq "stereo") {
      $ce->{stereo} = "stereo";
      push $extra->{qualifiers}, "stereo";
    }

    # Aspect
    if(defined($aspect) and $aspect eq "16:9") {
      $ce->{aspect} = "16:9";
      push $extra->{qualifiers}, "widescreen";
    } elsif(defined($aspect) and $aspect eq "4:3") {
      $ce->{aspect} = "4:3";
      push $extra->{qualifiers}, "smallscreen";
    }

    # credits
    ParseCredits( $ce, 'actors',     'actor',    $xpc, 'creditList/credit' );
    ParseCredits( $ce, 'directors',  'director', $xpc, 'creditList/credit' );
    ParseCredits( $ce, 'presenters', 'host',     $xpc, 'creditList/credit' );
    ParseCredits( $ce, 'guests',     'guest',    $xpc, 'creditList/credit' );

    # Data
    progress("Clipsource: $chd->{xmltvid}: $ce->{start_time} - $ce->{title}");
    $dsh->AddProgramme( $ce );

    $i2++;
  }


  # Success
  return 1;
}

# call with sce, target field, sendung element, xpath expression
sub ParseCredits
{
  my( $ce, $field, $type, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $func   = $node->findvalue( 'function' );
    my $person = $node->findvalue( 'name' );

    if( $func eq $type and norm($person) ne '' ) {
      push( @people, $person );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

# The start and end-times are in the format 2007-12-31T01:00:00.000Z
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  #print Dumper($str);

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "UTC"
  );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  my $url = sprintf( "http://clipsource.se/epg/api?key=%s&date=%s&channelId=%s", $self->{ApiKey}, $date, $data->{grabber_info});
  #my $url = sprintf( "http://clipsource.se/epg/xml/%s/%s/%s/download", $date, $date, $data->{grabber_info} );
  #my $url = "http://converter.xmltv.se/contentcache/Clipsource/dev.kanal5.se_2015-08-22.content.zip";

 progress("Fetching $url...");

  return( $url, undef );
}

sub ContentExtension {
  return 'zip';
}

sub FilterContent {
  my $self = shift;
  my( $zref, $chd ) = @_;

  my $cref;
  unzip $zref => \$cref;

  # remove
  $cref =~ s| xmlns="http://common.tv.se/schedule/v4_0"||g;
  $cref =~ s| xmlns="http://common.tv.se/event/v4_0"||g;
  $cref =~ s| xmlns="http://common.tv.se/content/v4_0"||g;
  $cref =~ s| xmlns="http://common.tv.se/material/v4_0"||g;
  $cref =~ s| xs="http://www.w3.org/2001/XMLSchema"||g;

  my $doc = ParseXml( \$cref );

  if( not defined $doc ) {
    return (undef, "Parse2Xml failed" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub FilteredExtension {
  return 'xml';
}

1;

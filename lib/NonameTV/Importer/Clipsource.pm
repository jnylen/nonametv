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

use NonameTV qw/ParseXml norm AddCountry AddCategory/;
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
      audio_format    => norm($mi->findvalue( 'audioList/format' ))
    };

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
    my $descs  = $xpc->findnodes( './/descriptionList/description', $row );
    my $desc   = undef;

    foreach my $t ($descs->get_nodelist)
    {
        if($t->findvalue( './@language' ) eq "swe" and $t->findvalue( './@type' ) eq "content") {
            $desc = norm($t->findvalue('./description'));
        }
    }

    my $title        = $xpc->findvalue( 'genericTitleList/title/title' );
    my $title_orgs   = $xpc->findnodes( 'titleList/title[@original="true"]' );

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
    foreach my $title_org2 ($title_orgs->get_nodelist)
    {
      my $title_org = $title_org2->findvalue("title");

      # Fix?
      if($title_org2->findvalue( './@language' ) eq "eng" and defined($title_org) and $title_org ne "") {
        if($title_org =~ /, The$/i)
        {
          $title_org =~ s/, The$//i;
          $title_org = "The " . $title_org;
        }
        if($title_org =~ /, A$/i)
        {
          $title_org =~ s/, A$//i;
          $title_org = "A " . $title_org;
        }
        if($title_org =~ /, An$/i)
        {
          $title_org =~ s/, An$//i;
          $title_org = "An " . $title_org;
        }

        $ce->{original_title} = norm($title_org) if norm($title_org) ne norm($title);
      }
    }

    # Genres
    my $genres  = $xpc->findnodes( 'genreList/genre' );
    foreach my $genre ($genres->get_nodelist) {
    #  my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Clipsource", $genre );
    #  AddCategory( $ce, $program_type, $category );
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

    # Rerun?
    if($rerun eq "true") {
      $ce->{new} = "0";
    } else {
      $ce->{new} = "1";
    }

    # Live?
    if($live eq "true") {
      $ce->{live} = "1";
    } else {
      $ce->{live} = "0";
    }

    # Audio?
    if(defined($a_format) and $a_format eq "mono") {
      $ce->{stereo} = "mono";
    } elsif(defined($a_format) and $a_format eq "stereo") {
      $ce->{stereo} = "stereo";
    }

    # Aspect
    if(defined($aspect) and $aspect eq "16:9") {
      $ce->{aspect} = "16:9";
    } elsif(defined($aspect) and $aspect eq "4:3") {
      $ce->{aspect} = "4:3";
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

  #my $url = sprintf( "http://clipsource.se/epg/api?key=%s&date=%s&channelId=%s", $self->{ApiKey}, $date, $data->{grabber_info});
  my $url = sprintf( "http://clipsource.se/epg/xml/%s/%s/%s/download", $date, $date, $data->{grabber_info} );
  #my $url = "http://converter.xmltv.se/contentcache/Clipsource/dev.kanal5.se_2015-08-22.content.zip";

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

package NonameTV::Importer::TV2_Norway;

use strict;
use warnings;

=pod

Importer for data from TV2 Norway.
One file per channel and week downloaded from their site.
The downloaded file is in xmltv-format.

Features:

=cut

use DateTime;
use XML::LibXML;
use Data::Dumper;
use Encode qw/encode decode/;
use TryCatch;

use NonameTV qw/ParseXml MyGet norm AddCountry AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    #defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//go; # Sometimes have invalid chars.

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }
  my $ns = $doc->find( "//programme" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    error "Failed to parse XML.";
    return 0;
  }

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );

  foreach my $sc ($ns->get_nodelist)
  {

    #
    # start time
    #
    my $start;
    try {
      $start = $self->create_dt( $sc->findvalue( './@start' ) );
    }
    catch ($err) { print("error: $err"); next; }

    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # title, subtitle
    #
    my ($title, $org_title);
    foreach my $t ($sc->getElementsByTagName('title'))
    {
        if(not defined($title)) {
            $title = norm($t->textContent());
        } else {
            $org_title = norm($t->textContent());
        }
    }

    my $subtitle = $sc->getElementsByTagName('sub-title');
    $title =~ s/\.$//;

    #
    # description
    #
    my $desc_series = $sc->findvalue( 'review[@source="series_long_synopsis"]' );
    my $desc_prog   = $sc->findvalue( 'review[@source="program_long_synopsis"]' );
    my $desc        = (norm($desc_prog) || norm($desc_series));

    #
    # genre
    #
    my $genre = $sc->find( './/category' );

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'date' );

    #
    # production country
    #
    my $country = $sc->getElementsByTagName( 'country' );

    #
    # episode number
    #
    my $episode = $sc->findvalue( 'episode-num[@system="xmltv_ns"]' );

    #
    # replay?
    #
    my $rerun = $sc->findvalue( 'episode-num[@system="dd_replay"]' );

    #
    # content?
    #
    my $content = $sc->findvalue( 'episode-num[@system="dd_content"]' );

    #
    # image
    #
    my $image = $sc->findvalue( 'episode-num[@system="dd_main-program-image"]' );

    # The director and actor info are children of 'credits'
    my $directors = parse_person_list($sc->find( 'credits/director' ));
    my $actors = parse_person_list($sc->find( 'credits/actor' ));
    my $writers = parse_person_list($sc->find( 'credits/writer' ));
    my $producers = parse_person_list($sc->find( 'credits/producer' ));
    my $commentators = parse_person_list($sc->find( 'credits/commentator' ));
    my $guests = parse_person_list($sc->find( 'credits/guest' ));
    my $presenters = parse_person_list($sc->find( 'credits/presenter' ));

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title) || norm($org_title),
      subtitle     => norm($subtitle),
      description  => norm($desc),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      directors    => norm($directors),
      actors       => norm($actors),
      writers      => norm($writers),
      presenters   => norm($presenters),
      commentators => norm($commentators),
      guests       => norm($guests),
    };

    if($ce->{title} =~ /^Film\:/i) {
        $ce->{title} =~ s/^Film\://gi;
        $ce->{title} = norm($ce->{title});
    }

    $ce->{title} =~ s/ - Sesongavslutning!//i;

    # Extra
    my $extra = {};
    $extra->{descriptions} = [];
    $extra->{qualifiers} = [];
    $extra->{images} = [];

  	my($program_type, $category ) = undef;

  	if(defined($genre)) {
  	    foreach my $g ($genre->get_nodelist)
          {
  		    ($program_type, $category ) = $ds->LookupCat( "TV2NO", $g->to_literal );
  		    AddCategory( $ce, $program_type, $category );
  		}
  	}

    if(defined($content)) {
      ($program_type, $category ) = $ds->LookupCat( "TV2NO_type", $content );
      AddCategory( $ce, $program_type, $category );
  	}

    if(defined ( $directors ) and ($directors ne "")) {
      $ce->{program_type} = 'movie';
    }

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    if(defined($country) and $country ne "") {
        my($country2 ) = $ds->LookupCountry( "TV2NO", norm($country) );
        AddCountry( $ce, $country2 );
    }

    # original title
    if($chd->{xmltvid} ne "sport.tv2.no" and defined($org_title) and lc($ce->{title}) ne lc(norm($org_title))) {
        $org_title =~ s/^Film\://gi;
        $ce->{original_title} = norm($org_title);

        # , The to THE
        if (defined $ce->{original_title} and $ce->{original_title} =~ /, The$/i) {
            $ce->{original_title} =~ s/, The$//i;
            $ce->{original_title} = "The ".$ce->{original_title};
        }
    }

    # image
    if(defined($image) and $image ne "" and $image !~ /bilde_mangler/i) {
        push @{$extra->{images}}, { url => $image, source => "TV2 Norway" };
    }

    # episode
    if( defined( $episode ) and ($episode =~ /\S/) )
    {
      $episode = norm($episode);
      $episode =~ s/\.\d+\/\d+$/\./;
      $ce->{episode} = norm($episode);
      $ce->{program_type} = 'series';
    }

    # replay
    if(defined($rerun) and norm($rerun) eq "true") {
      $ce->{new} = "0";
      push @{$extra->{qualifiers}}, "repeat";
    } else {
      $ce->{new} = "1";
    }

    $ce->{extra} = $extra;

    $ce->{subtitle} = undef;
    progress("TV2_Norway: $chd->{xmltvid}: $start - $ce->{title}");

    $ds->AddProgramme( $ce );
  }

  # Success
  return 1;
}


sub parse_person_list
{
  my( $str ) = @_;

  return undef if not defined $str;
  my @persons;
  my @persons2;

  # Each person
  foreach my $p ($str->get_nodelist)
  {
    push ( @persons, split(/, | og /, $p->to_literal));
  }

  foreach my $pp (@persons) {
    push @persons2, norm($pp);
  }

  return join( ";", grep( /\S/, @persons2 ) );
}

sub create_dt ( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $mili, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d\d\d)([+-]\d{2}:\d{2}|)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    if( $offset ){
      $offset =~ s|:||;
    } else {
      $offset = 'Europe/Oslo';
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => $offset
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

sub Object2Url {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ( $batch_id =~ /(\d+)-(\d+)$/ );

  my $url = sprintf( "https://rest.tv2.no/epg-dw-rest/xmltv/program/%01d/%01d",
                      $data->{grabber_info}, $week);

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

1;

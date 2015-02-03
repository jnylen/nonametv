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
use Encode qw/encode decode/;

use NonameTV qw/MyGet norm AddCountry AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );

  foreach my $sc ($ns->get_nodelist)
  {

    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
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
    my $desc  = $sc->getElementsByTagName('desc');

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
    # image
    #
    my $image = $sc->findvalue( 'icon/@src' );

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

    if(defined ( $directors ) and ($directors ne "")) {
      $ce->{program_type} = 'movie';
    }

    if($ce->{title} =~ /^Film\:/i) {
        $ce->{title} =~ s/^Film\://gi;
        $ce->{title} = norm($ce->{title});
    }

	my($program_type, $category ) = undef;

	if(defined($genre)) {
	    foreach my $g ($genre->get_nodelist)
        {
		    ($program_type, $category ) = $ds->LookupCat( "TV2NO", $g->to_literal );
		    AddCategory( $ce, $program_type, $category );
		}
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
    if(defined($org_title) and $ce->{title} !~ /^$org_title$/i) {
        $org_title =~ s/^Film\://gi;
        $ce->{original_title} = norm($org_title);

        # , The to THE
        if (defined $ce->{original_title} and $ce->{original_title} =~ /, The$/i) {
            $ce->{original_title} =~ s/, The$//i;
            $ce->{original_title} = "The ".$ce->{original_title};
        }
    }

    # image
    if(defined($image) and $image ne "") {
        #static.tv2.no/presse/images/medium/GREYSANATOMY_Y9_186_019.jpg => presse.tv2.no/presse/images/original/GREYSANATOMY_Y9_186_019.jpg
        $ce->{fanart} = $image;
        $ce->{fanart} =~ s/static\./presse\./;
        $ce->{fanart} =~ s/images\/medium/images\/original/;
    }

    # episode
    if( defined( $episode ) and ($episode =~ /\S/) )
    {
      $ce->{episode} = norm($episode);
      $ce->{program_type} = 'series';
    }

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

  # Each person
  foreach my $p ($str->get_nodelist)
  {
    push ( @persons, split(/, | og /, $p->to_literal));
  }

  return join( ";", grep( /\S/, @persons ) );
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

  my $url = sprintf( "http://rest.tv2.no/cms-tvguide-dw-rest/xmltv/%02d/%01d/channel/%s",
                     $year, $week, $data->{grabber_info});

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

1;

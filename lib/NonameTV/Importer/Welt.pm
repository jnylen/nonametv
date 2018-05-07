package NonameTV::Importer::Welt;

use strict;
use warnings;

=pod

Importer

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML;
use Try::Tiny;

use NonameTV qw/AddCategory norm/;
use NonameTV::Importer::BaseFile;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d progress w error f/;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Berlin" );
  $self->{datastorehelper} = $dsh;

  #$self->{datastore}->{augment} = 1;

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
  my $currdate = "x";

  progress( "Welt: $chd->{xmltvid}: Processing XML $file" );

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;
  $cref =~ s| xmlns="http://pid.rzp.hbv.de/xml/"||;

  my $xml = XML::LibXML->new;
  $xml->load_ext_dtd(0);
  my $doc = $xml->parse_string($cref);
  if (not defined ($doc)) {
    f ("$file   : Failed to parse.");
    return 0;
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//sendung" );
  if( $ns->size() == 0 ) {
    f ("$file: No data found");
    return 0;
  }

  foreach my $progs ($ns->get_nodelist) {
    my $ce = ();
    $ce->{channel_id} = $chd->{id};

    my $start = $self->parseTimestamp( $progs->findvalue( 'termin/@start' ) );
    my $end = $self->parseTimestamp( $progs->findvalue( 'termin/@ende' ) );

    next if(!defined($start));
    next if(!defined($end));
    my $date = $start->ymd("-");
    $ce->{start_time} = $start->hms(":");

    # Date
    if($date ne $currdate and $start->hour >= 6 ) {
      if( $currdate ne "x" ) {
        $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("Welt: Date is: $date");
    }

    $ce->{title} = norm($progs->findvalue( 'titel/@termintitel' ));

    my $title_org = $progs->findvalue( 'titel/alias[@titelart="originaltitel"]/@aliastitel' );
    $ce->{original_title} = norm($title_org) if $ce->{title} ne norm($title_org) and norm($title_org) ne "";

    my $subtitle = $progs->findvalue( 'titel/alias[@titelart="untertitel"]/@aliastitel' );

    if($title_org and $title_org ne "" and $title_org =~ /^(.*) S(\d+)E(\d+)/i ){
        $ce->{original_title} = norm($1);
        $ce->{episode} = ($2 - 1) . ' . ' . ($3 - 1) . ' .';
    }

    my $production_year = $progs->findvalue( 'infos/produktion/produktionszeitraum/jahr/@von' );
    if( $production_year =~ m|^\d{4}$| ){
      $ce->{production_date} = $production_year . '-01-01';
    }

    my $genre = $progs->findvalue( 'infos/klassifizierung/@hauptgenre' );
    if( $genre ){
      my ( $program_type, $category ) = $ds->LookupCat( "Welt", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    $ce->{subtitle} = norm($subtitle) if defined $subtitle and $subtitle ne "";
    $ce->{subtitle} = undef if defined($ce->{subtitle}) and $ce->{title} eq $ce->{subtitle};

    ParseCredits( $ce, 'presenters', $progs, 'mitwirkende/mitwirkender[@funktion="Moderation"]/mitwirkendentyp/person/name' );

    progress("Welt: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{2}:\d{2}|)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    if( $offset ){
      $offset =~ s|:||;
    } else {
      $offset = 'Europe/Berlin';
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => $offset
    );
    #$dt->set_time_zone( 'UTC' );

    return $dt;
  } else {
    return undef;
  }
}

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->findvalue( '@vorname' )." ".$node->findvalue( '@name' );

    if( norm($person) ne '' ) {
      push( @people, split( '&', $person ) );
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

1;

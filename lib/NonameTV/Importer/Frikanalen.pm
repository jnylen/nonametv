package NonameTV::Importer::Frikanalen;

use strict;
use warnings;

=pod

Importer for data from Frikanalen.
One file per day downloaded from their site.
The downloaded file is in xmltv-format.

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/MyGet norm AddCountry AddCategory/;
use NonameTV::Log qw/progress error w f p/;
use NonameTV::DataStore::Helper;

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

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

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

  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "00:00" );

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
    my $end = $self->create_dt( $sc->findvalue( './@end' ) );

    #
    # title
    #
    my $title = $sc->getElementsByTagName('title');

    #
    # description
    #
    #my $desc  = $sc->getElementsByTagName('desc');

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->hms(":"),
      end_time     => $end->hms(":")
    };

    progress("Frikanalen: $chd->{xmltvid}: $start - $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub create_dt ( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2}) ([+-]\d{2}\d{2}|)$/);
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

  my( $year, $month, $day ) = ( $batch_id =~ /(\d+)-(\d+)-(\d+)$/ );

  my $url = sprintf( "http://beta.frikanalen.no/xmltv/%d/%02d/%02d", $year, $month, $day );

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

1;

package NonameTV::Importer::ServusTV_JSON;

use strict;
use warnings;

=pod

Importer for data from ServusTV
One batch per day per channel.

format description:   http://struppi.tv/
VG Media EPG License: http://www.vgmedia.de/de/lizenzen/epg.html

=cut

use Data::Dumper;
use DateTime;
use JSON -support_by_pp;
use WWW::Mechanize::GZip;

use NonameTV qw/AddCategory AddCountry norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d progress w error f/;

use NonameTV::Importer::BaseDaily;
use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ContentExtension {
  return 'json';
}

sub FilteredExtension {
  return 'json';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref)->{"epgs"};

  # Date
  my( $date ) = ($batch_id =~ /_(.*)/);
  $dsh->StartDate( $date , "00:00" );

  # Sort by start
  #sub by_start {
  #  return $xpc->findvalue('@planungsDatum', $a) cmp $xpc->findvalue('@planungsDatum', $b);
  #}

  foreach my $p (@{$data}) {
    my $title = $p->{"broadcast"}->{"title"};
    my $start = ParseDateTime( $p->{"airing_start"} );

    # Put everything in a array
    my $ce = {
        channel_id => $chd->{id},
        start_time => $start->hms(":"),
        title => norm($title),
    };

    progress($start." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $u = "https://api.servustv.com/epgs?from_date=". $date ."T00%3A00%3A00%2B0200&to_date=". $date ."T23%3A59%3A59%2B0200";
  progress("ServusTV: fetching from: $u");

  my $ua = $self->{cc}->{ua};
  $ua->add_header('Accept-Language' => $chd->{grabber_info});
  my $res = $ua->get( $u );

  if( $res->is_success )
  {
    return ($res->content, undef );
  }
  else
  {
    return (undef, $res->status_line );
  }
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
      );

  return $dt;
}

1;

package NonameTV::Importer::Fjorton;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/f p/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{FtpRoot} ) or die "You must specify FtpRoot";
  defined( $self->{Filename} ) or die "You must specify Filename";

  my $conf = ReadConfig();

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Note: HTTP::Cache::Transparent caches the file and only downloads
  # it if it has changed. This works since LWP interprets the
  # if-modified-since header and handles it locally.

  my $url = $self->{FtpRoot} . '/' . $self->{Filename};

  return( $url, undef );
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

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 ) {
    f "No Programs found";
    return 0;
  }

  foreach my $emission ($ns->get_nodelist) {
    my $start_date = $emission->findvalue( './block/item[1]/@date' );
    my $start_time = $emission->findvalue( './block/item[1]/@start' );
    my $start_dt = create_dt($start_date, $start_time);
    next if(!defined $start_dt);

    my $title = norm( $emission->findvalue( './@name' ) );
    my $desc = norm( $emission->findvalue( './description' ) );

    my $ce = {
      channel_id => $channel_id,
      start_time => $start_dt->ymd('-') . ' ' . $start_dt->hms(':'),
      title => $title,
      description => $desc,
    };

    p($start_dt." $ce->{title}");

    $ds->AddProgramme( $ce );

  }

  return 1;
}

sub create_dt {
  my( $date, $time ) = @_;

  if($date eq "" or $time eq "") {
    return undef;
  }

  my($day, $month, $year ) = ($date =~ /^(\d+)\.(\d+)\.(\d\d\d\d)$/ );
  my( $hour, $minute ) = split(':', $time );

  my $dt = DateTime->new( year => $year,
                        month => $month,
                        day => $day,
                        hour => $hour,
                        minute => $minute,
                        time_zone => "Europe/Stockholm" );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

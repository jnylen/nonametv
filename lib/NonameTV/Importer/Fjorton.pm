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
use Try::Tiny;

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

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
  my $dsh = $self->{datastorehelper};

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

  my $currdate = "x";

  foreach my $emission ($ns->get_nodelist) {
    my $start_date = create_date($emission->findvalue( './block/item[1]/@date' ));
    my $start_time = create_time($emission->findvalue( './block/item[1]/@start' ));

    if( defined($start_date) and $start_date ne $currdate ) {
      if( $currdate ne "x" ) {
      #  $dsh->EndBatch( 1 );
      }

      my $batch_id = $chd->{xmltvid} . "_" . $start_date;
      #$dsh->StartBatch( $batch_id , $chd->{id} );
      $dsh->StartDate( $start_date , "00:00" );
      $currdate = $start_date;

      p("Fjorton: $chd->{xmltvid}: Date is: $start_date");
    }

    next if(!defined $start_time);

    my $title = norm( $emission->findvalue( './@name' ) );
    my $desc = norm( $emission->findvalue( './description' ) );

    my $ce = {
      channel_id => $channel_id,
      start_time => $start_time,
      title => $title,
      description => $desc,
    };

    p($start_time." $ce->{title}");

    try { $dsh->AddProgramme( $ce ); }
    catch { print("error: $_"); next; };

  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub create_date {
  my( $date ) = @_;

  if($date eq "") {
    return undef;
  }

  my($day, $month, $year ) = ($date =~ /^(\d+)\.(\d+)\.(\d\d\d\d)$/ );

  return sprintf("%04d-%02d-%02d", $year, $month, $day);
}

sub create_time {
  my( $time ) = @_;

  if($time eq "") {
    return undef;
  }

  my( $hour, $minute ) = split(':', $time );

  return sprintf("%02d:%02d", $hour, $minute);
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

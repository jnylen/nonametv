package NonameTV::Importer::RTLDE_HTML;

use strict;
use warnings;

=pod

Importer för ARIRANG airing worlwide.

=cut

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV qw/Html2Xml ParseXml AddCategory AddCountry norm/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Berlin" );
    $self->{datastorehelper} = $dsh;

    # use augment
    #$self->{datastore}->{augment} = 1;
    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );


  # Day=0 today, Day=1 tomorrow etc. Yesterday = yesterday

  my $dt = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day
                          );

  my $url = $self->{UrlRoot} . $dt->ymd( );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );

  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  my $str = $doc->toString(1);

  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'xml';
}


#
# 3 Zeilen pro Programm
#
# 00:00 - 15:00 # Host #
#
# <b>Title</b><br>
# Musikstyle: Stil<br>
#
# Gammel
#
sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};



  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }



  my $ns = $doc->find( '//div[@class="rtlde-epg-item "]' );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  # Start date
  my( $date ) = ( $batch_id =~ /(\d\d\d\d-\d\d-\d\d)$/ );
  $dsh->StartDate( $date , "06:00" );

  foreach my $pgm ($ns->get_nodelist) {
    my $time        = norm( $pgm->findvalue( './/div[@class="time rtli-h11 "]//text()' ) );
    my $title       = norm( $pgm->findvalue( './/h3[@class="title rtli-h13"]//text()' ) );

    my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title      => norm($title),
    };

    p($time." - $title");
    $dsh->AddProgramme( $ce );
  }

  return 1;
}


1;

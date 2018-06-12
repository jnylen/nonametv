package NonameTV::Importer::RheinmainTV;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;
use Data::Dumper;

use NonameTV qw/Html2Xml ParseXml normUtf8 norm/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if ($self->{MaxDays} >= 7) {
      $self->{MaxDays} = 7;
    }

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Berlin" );
    $self->{datastorehelper} = $dsh;

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

  my $url = "http://www.rheinmaintv.de/programm/tagesansicht/?daily=" . $dt->ymd( );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  $cref =~ s|^.+(<div class="accordion".+</div>).+<footer.+$|<html><body>$1</body></html>|s;

  my $doc = Html2Xml( $cref );

  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  my $str = $doc->toString(1);

  return( \$str, undef);
}

sub ContentExtension {
  return 'html.gz';
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

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( '//div[@class="accordion-group"]' );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  # Start date
  my( $date ) = ( $batch_id =~ /(\d\d\d\d-\d\d-\d\d)$/ );
  $dsh->StartDate( $date , "06:00" );
  p("Date is: $date");

  foreach my $pgm ($ns->get_nodelist) {
    my $time        = $pgm->findvalue( './/span//text()' );
    $time =~ s/UHR//i;
    my $title       = $pgm->findvalue( './/strong//text()' );
    my $ce = {
        channel_id  => $chd->{id},
        start_time  => norm($time),
        title => normUtf8($title),
    };

    p(norm($time)." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  return 1;
}


1;

package NonameTV::Importer::TV7;

=pod

This importer imports data for TV7 Heaven TV.
Including the Finnish, Estland, Swedish channels.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/norm ParseXmltv AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $id, $lang ) = split( /:/, $chd->{grabber_info} );

  my $url = 'http://amos.tv7.fi/exodus-interfaces/xmltv.xml?channel=' . $id . '&lang=' . $lang . '&duration=3w';

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $prog = ParseXmltv (\$$cref);
  my @shows = SortShows( @{$prog} );
  foreach my $e (@shows) {
    $e->{channel_id} = $chd->{id};

    # translate start end from DateTime to string
    $e->{start_dt}->set_time_zone ('UTC');
    $e->{start_time} = $e->{start_dt}->ymd('-') . " " . $e->{start_dt}->hms(':');
    delete $e->{start_dt};

    # some XMLTV exports don't provide programme "stop" time
    # helper is needed for such implementations
    $e->{stop_dt}->set_time_zone ('UTC');
    $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    # translate channel specific program_type and category to common ones
    my $pt = $e->{program_type};
    delete $e->{program_type};
    my $c = $e->{category};
    delete $e->{category};

    if( $pt ){
      my($program_type, $category ) = $ds->LookupCat( "TV7", $pt );
      AddCategory( $e, $program_type, $category );
    }
    if( $c ){
      my($program_type, $category ) = $ds->LookupCat( "TV7", $c );
      AddCategory( $e, $program_type, $category );
    }

    progress( "TV7: $chd->{xmltvid}: $e->{start_time} - $e->{title}" );
    $ds->AddProgramme($e);

  }



  # Success
  return 1;
}

sub bytime {

  my( $Y1, $M1, $D1, $h1, $m1, $s1 ) = ( $$a{start_dt} =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)$/ );
  my $t1 = int( sprintf( "%04d%02d%02d%02d%02d%02d", $Y1, $M1, $D1, $h1, $m1, $s1 ) );

  my( $Y2, $M2, $D2, $h2, $m2, $s2 ) = ( $$b{start_dt} =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)$/ );
  my $t2 = int( sprintf( "%04d%02d%02d%02d%02d%02d", $Y2, $M2, $D2, $h2, $m2, $s2 ) );

  $t1 <=> $t2;
}

sub SortShows {
  my ( @shows ) = @_;

  my @sorted = sort bytime @shows;

  return @sorted;
}


1;

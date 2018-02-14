package NonameTV::Importer::DR_Json;

use strict;
use utf8;
use warnings;

=pod

Importer for DR.dk
The file downloaded is in JSON format.

=cut

use DateTime;
use JSON -support_by_pp;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

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

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = "http://www.dr.dk/mu/Schedule/". $date ."%40".$chd->{grabber_info}."?merge=True";

  return( $url, undef );
}


sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;


  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Date
  my( $date ) = ($batch_id =~ /_(.*)/);
  $dsh->StartDate( $date , "00:00" );

  # Data
  my $json = new JSON->allow_nonref;
  my $parse = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

  if( $parse->{'TotalSize'} == 0) {
    error( "DR_Json: $chd->{xmltvid}: No data found" );
    return;
  }

  # The broadcasts are here
  my $data = $parse->{"Data"}[0]->{'Broadcasts'};

  foreach my $p (@{$data}) {
    my $start = ParseDateTime( $p->{"AnnouncedStartTime"} );
    my $end = ParseDateTime( $p->{"AnnouncedEndTime"} );
    my $title = $p->{"Title"};
    my $year = $p->{"ProductionYear"};
    my $desc = $p->{"Description"};

    # Add
    my $ce = {
      channel_id => $chd->{id},
      start_time => $start->hms(":"),
      title      => norm($title),
    };

    $ce->{production_date} = "$year-01-01" if defined($year) and $year ne "";
    $ce->{description}     = norm($desc)   if defined($desc) and $desc ne "";

    progress($start." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  return 1;
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

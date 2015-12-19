package NonameTV::Importer::RTLDE;

use strict;
use utf8;
use warnings;

=pod

Importer for RTL Deutschland (VOX, RTL, RTL Nitro, n-tv, Super RTL, RTL2)
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

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    $self->{datastore}->{augment} = 1;

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

  my $url = $self->{UrlRoot} . "/v3/epgs/movies/".$chd->{grabber_info}."/".$date."?fields=*,movie.*,movie.format,movie.paymentPaytypes,movie.pictures,movie.trailers,epgImages,epgImages.*,epgFormat,*.*";

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
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref)->{"items"};

  my ($p, $start_of_week, $folge);

  foreach $p (@{$data}) {
    my $title = $p->{"title"};
    my $subtitle = $p->{"subTitle"};

    # Start and so on
    my $start = ParseDateTime( $p->{"startDate"} );
    my $end   = ParseDateTime( $p->{"endDate"} );
    my $diff  = $end - $start;

    # Put everything in a array
    my $ce = {
        channel_id => $chd->{id},
        start_time => $start->hms(":"),
        end_time   => $end->hms(":"),
        title      => norm($title),
    };

    if(defined($subtitle) and $subtitle ne "") {
      if( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
        $ce->{episode} = '. ' . ($folge - 1) . ' .';
        $ce->{program_type} = "series";
      } else {
        $ce->{subtitle} = norm($subtitle);
        $ce->{program_type} = "series";
      }
    }elsif($diff->in_units('minutes') > 90 and (!defined($p->{"movie"}) or !$p->{"movie"}) and (!defined($p->{"epgFormat"}->{"epgFormat"}) or $p->{"epgFormat"}->{"epgFormat"} eq "")) {
      $ce->{program_type} = "movie";
    }


    progress($start." $ce->{title}");

    $dsh->AddProgramme( $ce );

  #  $dsh->AddProgramme( $ce );
  }
  return 1;
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
      );

  return $dt;
}

1;

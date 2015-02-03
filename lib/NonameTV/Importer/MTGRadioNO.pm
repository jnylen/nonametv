package NonameTV::Importer::MTGRadioNO;

use strict;
use utf8;
use warnings;

=pod

Importer for MTG Radio Norway (Bandit, P4 etc.)
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
    $self->{NO_DUPLICATE_SKIP} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = $self->{UrlRoot} . "?method=EPG&stationId=".$chd->{grabber_info}."&d=".$date;

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

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "00:00" );

  foreach my $p (@{$data}) {
    my $title = $p->{"Name"};
    my $start = $self->create_dt($p->{"StartDateTime"});
    my $end = $self->create_dt($p->{"EndDateTime"});
    my $desc = $p->{"Description"};

    my @hosts;

    # Hosts
    foreach my $h (@{$p->{"Hosts"}}) {
        push @hosts, $h->{"Name"};
    }

    # Put everything in a array
    my $ce = {
        channel_id => $chd->{id},
        start_time => $start->hms(),
        end_time => $end->hms(),
        title => norm($title),
        description => norm($desc),
    };

    if( scalar( @hosts ) > 0 )
    {
      $ce->{presenters} = join ";", @hosts;
    }

    progress($start." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }


  return 1;
}


sub create_dt ( $ )
{
  my $self = shift;
  my ($timestamp, $date) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
    if( !defined( $year )|| !defined( $hour ) || ($month < 1) ){
      w( "could not parse timestamp: $timestamp" );
      return undef;
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => 'UTC'
    );
    #$dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;
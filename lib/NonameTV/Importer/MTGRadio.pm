package NonameTV::Importer::MTGRadio;

use strict;
use utf8;
use warnings;

=pod

Importer for MTG Radio (Bandit, RIX FM etc.)
The file downloaded is in JSON format.

=cut

use DateTime;
use JSON -support_by_pp;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

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

sub ContentExtension {
  return 'json';
}

sub FilteredExtension {
  return 'json';
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = $self->{UrlRoot} . "/md/v0/".$chd->{grabber_info}."/getepg/week";

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

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

  my ($date, $p, $start_of_week);

  # For each 4 weeks and days
  for( my $week=0; $week <= 4; $week++ ) {
    # Week
    $start_of_week = DateTime->today()->truncate( to => 'week' )->add( weeks => $week);

    for( my $day=0; $day <= 6; $day++ ) {
        $date = $start_of_week->clone()->add( days => $day );

        # programmes
        foreach $p (@{$data}) {
            # Can only be the same day
            if(defined($p->{"day_of_week"}) and ($day + 1) eq $p->{"day_of_week"} ) {
                my $title = $p->{"program_name"};
                my $desc = $p->{"description"};
                my $start = $p->{"start_time"};
                my $end = $p->{"end_time"};

                # Otherwise it will whine
                if( $date->ymd("-") ne $currdate ){
                    progress("Date is ".$date->ymd("-"));

                    $dsh->StartDate( $date->ymd("-") , "00:00" );
                    $currdate = $date->ymd("-");
                }

                # Put everything in a array
                my $ce = {
                    channel_id => $chd->{id},
                    start_time => $start,
                    end_time => $end,
                    title => norm($title),
                    description => norm($desc),
                };

                progress($start." $ce->{title}");

                $dsh->AddProgramme( $ce );
            }
        }
    }

  }
  return 1;
}

1;

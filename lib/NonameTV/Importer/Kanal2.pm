package NonameTV::Importer::Kanal2;

use strict;
use utf8;
use warnings;

=pod

Importer for Kanal 2, Kanal 11, Kanal 12.
The file downloaded is in JSON format.

=cut

use DateTime;
use JSON -support_by_pp;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/norm ParseJson AddCategory/;
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

  my $url = $self->{UrlRoot} . $chd->{grabber_info}."/json?start=".$date."&end=".$date;

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

  # Parse
  my $data = ParseJson($cref);

  # Date
  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "05:00" );

  # programmes
  foreach my $p (@{$data}) {
    my $datetime = $p->{"telecast_datetime"};
    my( $time ) = ($datetime =~ / (\d\d\:\d\d\:\d\d)$/);

    my $title = $p->{"telecast"};
    my $subtitle = $p->{"subtitle"};

    my $desc = $p->{"description"};
    my $ep_nr = $p->{"episode_nr"};

    my $org_title = $p->{"original_title"};

    my $prodyear = $p->{"creator_year"};
    my $director = $p->{"creator_director"};
    my $actors = $p->{"creator_actors"};
    my $prodcountry = $p->{"creator_country"};

    my $type = $p->{"telecast_type"};

    my $ce = {
      title       	 => norm($title),
      description    => norm($desc),
      start_time  	 => $time,
    };

    # Genres and category
    my( $pty, $cat );
    if(defined($type) and $type and $type ne "") {
        ( $pty, $cat ) = $ds->LookupCat( 'Kanal2_type', $type );
        AddCategory( $ce, $pty, $cat );
    }

    # Episode
    if($type ne "M" and defined($ep_nr) and $ep_nr ne "" and $ep_nr =~ /(\d+)/) {
      $ce->{episode} = sprintf( " . %d . ", $1-1 ) if($1 > 0);
    }

    # Org title
    $ce->{original_title} = norm($org_title) if $org_title and $org_title ne $title;

    # Prod year
    if( $prodyear =~ /(\d\d\d\d)/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # Actors
    my @actorss = split(", ", $actors);
    if( scalar( @actorss ) > 0 )
    {
      $ce->{actors} = join ";", @actorss;
    }

    # Directors
    my @directors = split(", ", $director);
    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ";", @directors;
    }

    progress($date." ".$time." - ".$ce->{title});
    $dsh->AddProgramme( $ce );
  }

  return 1;
}

1;
package NonameTV::Importer::TV2Reg;

use strict;
use warnings;

=pod

Importer for data from TV2 Regional.
One file per channel and ?-day period downloaded from their site.
The downloaded file is in rss-format.

Features:

=cut

use DateTime;
use Data::Dumper;
use XML::LibXML;
use Encode qw/encode decode/;
use TryCatch;

use NonameTV qw/MyGet norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
    $self->{datastorehelper} = $dsh;

    return $self;
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

  my $currdate = "x";

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }

  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( tv2r => 'http://www.tv2reg.dk/namespace/' );

  my $rows = $xpc->findnodes( '//rss/channel/item', $doc );

  if( $rows->size() == 0 ) {
    error( "TV2Reg: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  foreach my $program ($rows->get_nodelist) {
    $xpc->setContextNode( $program );

    my $dt;
    try {
      $dt    = $self->create_dt($xpc->findvalue( 'pubDate' ));
    }
    catch ($err) { print("error: $err"); next; }

    my $duration  = $xpc->findvalue( 'tv2r:varighed' );
    my $title     = $xpc->findvalue( 'title' );
    my $desc      = $xpc->findvalue( 'description' );
    my $longdesc  = $xpc->findvalue( 'longDescription' );
    my $genre     = $xpc->findvalue( 'tv2r:kategori' );
    my $seriestit = $xpc->findvalue( 'tv2r:serienavn' );

    $title = "Nyheder" if(norm($title) =~ /Nyheder$/i); # It's a series

    # Start a new date
    if($dt->ymd("-") ne $currdate ) {

      $dsh->StartDate( $dt->ymd("-") , "06:00" );
      $currdate = $dt->ymd("-");
      progress("TV2Reg: $chd->{xmltvid}: Date is: $currdate");
    }

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm(($title || $seriestit)),
      description  => norm(($longdesc || $desc)),
      start_time   => $dt->hms,
    };

    # genre
    if($genre and $genre ne "") {
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "TV2Reg", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    # production year
    if( $seriestit =~ /(\d\d\d\d)$/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # episode is in the title
    my ( $epnum, $ofeps );
    if( ( $epnum, $ofeps ) = ($ce->{title} =~ /(\d+):(\d+)$/) )
    {
        $ce->{title} =~ s/$epnum:$ofeps$//;
        $ce->{title} = norm($ce->{title});
        $ce->{episode} = sprintf( " . %d/%d . ", $epnum-1, $ofeps );
    }elsif( ( $epnum, $ofeps ) = ($ce->{title} =~ /\((\d+):(\d+)\)$/) )
    {
        $ce->{title} =~ s/\($epnum:$ofeps\)$//;
        $ce->{title} = norm($ce->{title});
        $ce->{episode} = sprintf( " . %d/%d . ", $epnum-1, $ofeps );
    }elsif( ( $epnum ) = ( $ce->{title} =~ /\((\d+)\)$/ ) )
    {
        $ce->{title} =~ s/\($epnum\)$//;
        $ce->{title} = norm($ce->{title});
        $ce->{episode} = sprintf( " . %d . ", $epnum-1 );
    }

    my $extra = {};
    #$extra->{descriptions} = [];
    $extra->{qualifiers} = [];

    # Additional data, which isn't required, but is nice
    my $live    = $xpc->findvalue( 'tv2r:live' );
    my $rerun   = $xpc->findvalue( 'tv2r:genudsendelse' );
    my $catchup = $xpc->findvalue( 'tv2r:streaming_ondemand' );

    # Tags
    if($live eq "true") {
      $ce->{live} = "1";
      push @{$extra->{qualifiers}}, "live";
    } else {
      $ce->{live} = "0";
    }

    if($rerun eq "true") {
      $ce->{new} = "0";
      push @{$extra->{qualifiers}}, "rerun";
    } elsif($live ne "true") {
      $ce->{new} = "1";
      push @{$extra->{qualifiers}}, "new";
    }

    if($catchup eq "true") {
      push $extra->{qualifiers}, "catchup";
    }

    $ce->{extra} = $extra;


    # This program is part of a series and it has a colon in the title.
    # Assume that the colon separates the title from the subtitle.
    if( defined($ce->{program_type}) and ($ce->{program_type} eq 'series') ) {
      my( $t, $dumbie, $st ) = ($ce->{title} =~ /(.*?)( -|:) (.*)/);
      if( defined( $st ) )
      {
        $ce->{title} = norm($t);

        # Needs ucfirst if there is no uppercase
        if (norm($st) !~ /[A-Z]/ or norm($st) !~ /\p{Uppercase}/) {
          $ce->{subtitle} = ucfirst(norm($st));
        } else {
          $ce->{subtitle} = norm($st);
        }

      }
    }

    # credits
    ParseCredits( $ce, 'presenters',     'V.rt',        $xpc, 'tv2r:cast/tv2r:person' );
    #ParseCredits( $ce, 'producers',      'Producer',    $xpc, 'tv2r:cast/tv2r:person' ); # their format is Jesper Jørgensen, Producent, Wasabi Film

    progress("TV2Reg: $chd->{xmltvid}: $dt - $ce->{title}");
    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

# call with sce, target field, sendung element, xpath expression
sub ParseCredits
{
  my( $ce, $field, $type, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $func   = $node->findvalue( 'tv2r:funktion' );
    my $person = $node->findvalue( 'tv2r:navn' );

    if( $func =~ /^$type$/i and norm($person) ne '' ) {
      push( @people, $person );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}

sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

sub create_dt ( $ )
{
  my $self = shift;
  my ($timestamp, $date) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($day, $monthname, $year, $hour, $minute) = ($timestamp =~ m/, (\d+) (.*?) (\d\d\d\d) (\d\d):(\d\d)/);
    my $month;

    $month = MonthNumber( $monthname, "en" );

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => 'Europe/Stockholm'
    );
    #$dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = sprintf( "http://www.tv2reg.dk/won/program/program_%s.xml", $chd->{grabber_info} );

  return( $url, undef );
}

1;

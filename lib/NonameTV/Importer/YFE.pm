package NonameTV::Importer::YFE;

use strict;
use warnings;

=pod

Import data from YFE

Channels: FIX&FOXI and RiC

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;
use XML::LibXML;
use XML::LibXML::XPathContext;

use NonameTV qw/norm AddCategory AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

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

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;
  my $chanfileid = $chd->{grabber_info};

  if( $file =~ /$chanfileid/i and $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.zip$/i ) {

    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @files;
    my @members = $zip->members();
    foreach my $member (@members) {
      push( @files, $member->{fileName} ) if $member->{fileName} =~ /$chanfileid/i and $member->{fileName} =~ /xml$/i;
    }

    my $numfiles = scalar( @files );
    if( $numfiles eq 0 ) {
      f "Found 0 matching files, expected more than that.";
      return 0;
    }

    foreach my $zipfile (@files) {
        d "Using file $zipfile";
        # file exists - could be a new file with the same filename
        # remove it.
        my $filename = '/tmp/'.$zipfile;
        if (-e $filename) {
            unlink $filename; # remove file
        }

        my $content = $zip->contents( $zipfile );

        open (MYFILE, '>>'.$filename);
        print MYFILE $content;
        close (MYFILE);

        $self->ImportXML( $filename, $chd );
        unlink $filename; # remove file
    }
  } else {
    error( "YFE: Unknown file format: $file" );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns:ns='http://struppi.tv/xsd/'||;
  $cref =~ s| xmlns:xsd='http://www.w3.org/2001/XMLSchema'||;

  $cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;


  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if (not defined ($doc)) {
    f ("$file: Failed to parse.");
    return 0;
  }

  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( s => 'http://struppi.tv/xsd/' );

  my $programs = $xpc->findnodes( '//s:sendung', $doc );
  if( $programs->size() == 0 ) {
    f ("$file: No data found");
    return 0;
  }

  sub by_start {
    return $xpc->findvalue('s:termin/@start', $a) cmp $xpc->findvalue('s:termin/@start', $b);
  }

  my $currdate = "x";

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week, $year) = ($file =~ /week(\d+)_(\d\d\d\d)/);

  if(!defined $year) {
      error( "$file: $chd->{xmltvid}: Failure to get year from filename" ) ;
      return;
  }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );

  ## END

  foreach my $program (sort by_start $programs->get_nodelist) {
    $xpc->setContextNode( $program );
    my $start = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
    my $end = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) );
    my $ce = ();
    $ce->{channel_id} = $chd->{id};

    $ce->{start_time} = $start->ymd("-") . " " . $start->hms(":");
    $ce->{end_time} = $end->ymd("-") . " " . $end->hms(":");

    if($start->ymd("-") ne $currdate ) {
      #$dsh->StartDate( $start->ymd("-") , "06:00" );
      $currdate = $start->ymd("-");
      progress("YFE: $chd->{xmltvid}: Date is: ".$start->ymd("-"));
    }

    $ce->{title} = norm($xpc->findvalue( 's:titel/@termintitel' ));
    my ($folge, $staffel);
    my $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="untertitel"]/@aliastitel' );
    my $subtitle_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaluntertitel"]/@aliastitel' );
    if( $subtitle ){
      if( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \((\d+)\. Staffel\)$| ) ){
        $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
      } elsif( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \(Staffel (\d+)\)$| ) ){
        $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
      } elsif( ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
        $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
      } elsif( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
        $ce->{episode} = '. ' . ($folge - 1) . ' .';
      } else {
        # unify style of two or more episodes in one programme
        $subtitle =~ s|\s*/\s*| / |g;
        # unify style of story arc
        $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
        $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
        $ce->{subtitle} = norm( $subtitle );
      }
    }

    my $production_year = $xpc->findvalue( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionszeitraum/s:jahr/@von' );
    if( $production_year =~ m|^\d{4}$| ){
      $ce->{production_date} = $production_year . '-01-01';
    }

    my @countries;
    my $ns4 = $xpc->find( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionsland/@laendername' );
    foreach my $con ($ns4->get_nodelist)
    {
        my ( $c ) = $self->{datastore}->LookupCountry( "YFE", $con->to_literal );
        push @countries, $c if defined $c;
    }
    if( scalar( @countries ) > 0 )
    {
          $ce->{country} = join "/", @countries;
    }

    my $season  = $xpc->findvalue( 's:infos/s:folge/@staffel' );
    my $episode = $xpc->findvalue( 's:infos/s:folge/@folgennummer' );

    if(defined($episode) and $episode and $episode ne "") {
        if(defined($season) and $season and $season ne "") {
            $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
        } else {
            $ce->{episode} = ' . ' . ($episode - 1) . ' .';
        }
    }

    my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@kategorie' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "YFE_genre", $genre );
      AddCategory( $ce, $program_type, $category );
    }
    $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
    if( $genre ){
      my ( $program_type2, $category2 ) = $self->{datastore}->LookupCat( "YFE_main", $genre );
      AddCategory( $ce, $program_type2, $category2 );
    }

    ParseCredits( $ce, 'actors',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Darsteller"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'directors',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Regie"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'producers',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Produzent"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Autor"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Drehbuch"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'presenters', $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Moderation"]/s:mitwirkendentyp/s:person/s:name' );
    ParseCredits( $ce, 'guests',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Gast"]/s:mitwirkendentyp/s:person/s:name' );

    $ds->AddProgrammeRaw( $ce );

    progress("YFE: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});

  }

  $dsh->EndBatch( 1 );

  return 1;
}

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->findvalue( '@vorname' )." ".$node->findvalue( '@name' );

    if( norm($person) ne '' ) {
      push( @people, split( '&', $person ) );
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

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $milliseconds) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d+)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => 'Europe/Berlin'
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;

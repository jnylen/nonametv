package NonameTV::Importer::Horse1;

=pod

Imports data for Horse1 using their homepage.
Okeyed by them.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/MyGet normLatin1 Html2Xml ParseXml AddCategory AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    if( defined( $self->{UrlRoot} ) ){
        warn( 'UrlRoot is deprecated' );
    }else{
        $self->{UrlRoot} = 'http://www.horse1.se/tv-tabla';
    }

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  return( "http://www.horse1.se/tv-tabla", undef );
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

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }

  my $ns = $doc->find( '//div[@class="cols cols3"]//div[@class="col"]//ul//li' );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }
  my $currdate = "x";

  foreach my $pgm ($ns->get_nodelist)
  {
    # The data consists of alternating rows with time+title or description.
    my $datetime = ParseDateTime( $pgm->findvalue( './/article//time/@datetime' ) );
    my $date = $datetime->ymd("-");
    my $time = $datetime->hms(":");

    # Startdate
    if( $date ne $currdate ) {
      progress("Horse1: $chd->{xmltvid}: Date is $date");
      $dsh->StartDate( $date , "06:00" );
      $currdate = $date;
    }

    my $title = normLatin1( $pgm->findvalue( './/article//header//h3//text()' ) );
    $title =~ s/\s+\s+/ - /;
    my $image = normLatin1( $pgm->findvalue( './/article//a//img//@data-original' ) );
    my $url = normLatin1( $pgm->findvalue( './/article//a/@href' ) );

    # We should probably also fetch the urls from the a href in order to find episode-specific
    # description.
    my $shortdesc = normLatin1( $pgm->findvalue( './/article//a//p[1]//text()' ) );

    # Create ce
    my $ce = {
      channel_id => $chd->{channel_id},
      title => normLatin1( $title ),
      start_time => $time,
      description => $shortdesc,
    };

    ## Stuff
    my @sentences = (split_text( $shortdesc ), "");
    my $season = "0";
    my $episode = "0";
    my $eps = "0";

    for( my $i2=0; $i2<scalar(@sentences); $i2++ )
    {
      if( my( $dummy, $seasontextnum12 ) = ($sentences[$i2] =~ /^S(.*?)song (\d+)\./i ) )
      {
        $season = $seasontextnum12;

        # Only remove sentence if it could find a season
        if($season ne "") {
          $sentences[$i2] = "";
        }
      }elsif( my( $episodetextnum4, $ofepisode2 ) = ($sentences[$i2] =~ /Del (\d+)\/(\d+)\./i ) )
      {
        $episode = $episodetextnum4;
        $eps = $ofepisode2;

        # Only remove sentence if it could find a season
        if($episode ne "") {
            $sentences[$i2] = "";
          }
      }elsif( my ( $genre, $country, $year ) = ($sentences[$i2] =~ /^(.*?), (.*?) (\d\d\d\d)\./i ) )
      {
        # Genre
        my ( $pty, $cat ) = $ds->LookupCat( 'Horse1', normLatin1($genre) );
	  	  AddCategory( $ce, $pty, $cat );

        # Country
        my($country2 ) = $ds->LookupCountry( "Horse1", normLatin1($country) );
        AddCountry( $ce, $country2 );

        $ce->{production_date} = "$year-01-01";

        # Only remove sentence if it could find a season
        if($episode ne "") {
            $sentences[$i2] = "";
          }
      }
    }

    $ce->{description} = join_text( @sentences );

    # Episode info in xmltv-format
    if( ($episode ne "0") and ( $eps ne "0") and ( $season ne "0") )
    {
      $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $eps );
    }
    elsif( ($episode ne "0") and ( $eps ne "0") )
    {
        $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $eps );
    }
    elsif( ($episode ne "0") and ( $season ne "0") )
    {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }
    elsif( $episode ne "0" )
    {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    # Image
    if(defined($image) and $image ne "") {
      $image =~ s/220\.img/940\.img/i;
      $ce->{fanart} = $image;
    }

    # URL
    if(defined($url) and $url ne "") {
      $ce->{url} = "http://www.horse1.se/" . $url;
    }

    progress("Horse1: $chd->{xmltvid}: $time - $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm()
  # Replace newlines followed by a capital with space and make sure that there
  # is a dot to mark the end of the sentence.
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([\(A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute ) =
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $u = "http://www.horse1.se/tv-tabla";
  progress("Horse1: fetching from: $u");

  my( $content, $code ) = MyGet( $u );

  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

}

1;

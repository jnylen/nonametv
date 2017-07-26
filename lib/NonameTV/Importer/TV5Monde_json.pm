package NonameTV::Importer::TV5Monde_json;

use strict;
use utf8;
use warnings;

=pod

Importer for TV5 Monde.
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

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Paris" );
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

  my $url = "http://europe.tv5monde.com/sites/default/files/schedule-json-".$chd->{grabber_info}.".json";

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

  my ($p, $folge, $subtitle2);

  foreach $p (@{$data}) {
    my $title = $p->{"t"};
    $title = ucfirst(lc($title));
    $title =~ s/tv5monde/TV5Monde/i;
    my $desc = $p->{"d"};
    $desc =~ s/<p>//ig;
    $desc =~ s/<\/p>//ig;
    $desc =~ s/<br \/>//ig;
    my $genre = $p->{"c"};

    # Start and so on
    my $start = ParseDateTime( $p->{"b"}->{"value"} );

    # Put everything in a array
    my $ce = {
        channel_id => $chd->{id},
        start_time => $start,
        title      => norm($title),
    };

    # Description
    my @sentences = split_text( $desc );
    my ($episode, $season, $stoopid4);

    for( my $i=0; $i<scalar(@sentences); $i++ )
    {
      if( my( $stoopid3, $directors, $country, $year ) = ($sentences[$i] =~ /^(Directed by|Direction):\s*(.*) \((.*?), (\d\d\d\d)\)/) )
      {
          $ce->{directors} = parse_person_list( $directors );
          $ce->{production_date} = $year. "-01-01";

          # Season?
          if(!defined($season)) {
            ($stoopid4, $season) = ($country =~ /(season|saison) (\d+)/i);
          }

          $sentences[$i] = "";
      }
      elsif( my( $stoopid2, $directors2 ) = ($sentences[$i] =~ /^(Directed by|Direction):\s*(.*)/) )
      {
          $ce->{directors} = parse_person_list( $directors2 );
          $sentences[$i] = "";
      }
      elsif( my ( $episode2, $subtitle ) = ($sentences[$i] =~ /^Episode (\d+)\: (.*)/) )
      {
        $episode = $episode2;
        $ce->{subtitle} = norm($subtitle);
        $sentences[$i] = "";
      }
      elsif( my ( $episode2 ) = ($sentences[$i] =~ /^Episode (\d+)/) )
      {
        $episode = $episode2;
        $sentences[$i] = "";
      }
      elsif( my( $stoopid, $actors ) = ($sentences[$i] =~ /^(Cast|With):\s*(.*)/ ) )
      {
          $ce->{actors} = parse_person_list( $actors );
          $sentences[$i] = "";
      }
      elsif( my( $dump, $guests ) = ($sentences[$i] =~ /^Guest(s|):\s*(.*)/ ) )
      {
          $ce->{guests} = parse_person_list( $guests );
          $sentences[$i] = "";
      }
      elsif( my( $presenters ) = ($sentences[$i] =~ /^Presented by:\s*(.*)/ ) )
      {
          $ce->{presenters} = parse_person_list( $presenters );
          $sentences[$i] = "";
      }
      elsif( my( $presenters ) = ($sentences[$i] =~ /^Screenplay:\s*(.*)/ ) )
      {
          $sentences[$i] = "";
      }
      elsif( my( $stoopid47 ) = ($sentences[$i] =~ /^Genre:\s*(.*)/ ) )
      {
          $sentences[$i] = "";
      }
      elsif( my( $stoopid47 ) = ($sentences[$i] =~ /^Parental guidance:\s*(.*)/ ) )
      {
          $sentences[$i] = "";
      }
      elsif( my( $stoopid47 ) = ($sentences[$i] =~ /^Awards:\s*(.*)/ ) )
      {
          $sentences[$i] = "";
      }
      elsif( my( $stoopid47 ) = ($sentences[$i] =~ /^Website:\s*(.*)/ ) )
      {
          $sentences[$i] = "";
      }
    }

    if( defined($episode) and defined($season) and ($episode ne "0" and $episode ne "") and ( $season ne "0" and $season ne "") )
    {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }
    elsif( defined($episode) and $episode ne "0" and $episode ne "" )
    {
      if( defined( $ce->{production_date} ) and ($ce->{production_date} =~ /(\d\d\d\d)/) ) {
        $ce->{episode} = sprintf( "%d . %d .", $1-1, $episode-1 );
      } else {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

    }

    $ce->{description} = join_text( @sentences );
    $ce->{description} = undef if($ce->{description} eq "Pas de description pour ce programme.");

    progress($start." - $ce->{title}");
    $ds->AddProgramme( $ce );
  }
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

sub parse_person_list
{
  my( $str ) = @_;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\band\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
    s/^\.$//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/ );

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

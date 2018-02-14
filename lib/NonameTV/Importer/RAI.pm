package NonameTV::Importer::RAI;

use strict;
use warnings;
use utf8;
use Unicode::String;

=pod

Import data for RAI in xml-format.

=cut


use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/Html2Xml ParseXml AddCategory AddCountry norm normUtf8 normLatin1/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Rome" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
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

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//li" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  # Start date
  my( $date ) = ( $batch_id =~ /(\d\d\d\d-\d\d-\d\d)$/ );
  $dsh->StartDate( $date , "06:00" );

  foreach my $pgm ($ns->get_nodelist) {
    my $time        = norm( $pgm->findvalue( './/span[@class="ora"]//text()' ) );
    my $title       = norm( $pgm->findvalue( './/span[@class="info"]//text()' ) );
    my $desc        = $pgm->findvalue( './/div[@class="eventDescription"]//text()' );
    my $desc_extra  = $pgm->findvalue( './/div[@class="eventDescription"]//span[@class="solotesto"]//text()' );

    #$desc =~ s/$desc_extra//i;

    my $ce = {
      channel_id  => $chd->{id},
      start_time  => $time,
      title       => norm($title),
      description => norm($desc),
    };

    # Title
    if( $title =~ /^FILM/  ) {
    	$ce->{title} =~ s/^FILM//g; # REMOVE ET
    	$ce->{program_type} = 'movie';
    }elsif( $title =~ /^TELEFILM/  ) {
        $ce->{title} =~ s/^TELEFILM//g; # REMOVE ET
        $ce->{program_type} = 'series';
    }elsif( $title =~ /^TV MOVIE/  ) {
        $ce->{title} =~ s/^TV MOVIE//g; # REMOVE ET
        $ce->{program_type} = 'series';
    }elsif( $title =~ /^MOVIE/  ) {
        $ce->{title} =~ s/^MOVIE//g; # REMOVE ET
    }

    # Clean up
    $ce->{title} = norm($ce->{title});
    $ce->{title} =~ s/^- //;


    # Desc
    my @desc_extra_sentences = split_text( $desc_extra );
    if( $desc_extra_sentences[0] =~ /^FILM/  ) {
        $ce->{program_type} = 'movie';
    }

    for( my $i=0; $i<scalar(@desc_extra_sentences); $i++ )
    {
      if($i eq "0" and norm($desc_extra_sentences[$i]) =~ /^(.*?)\s+-/) {
        my ($genre) = ($desc_extra_sentences[$i] =~ /^(.*?)\s+-/ );
        if(defined($genre)) {
          $genre = lc($genre);
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "RAI", $genre );
          AddCategory( $ce, $program_type, $category );
        }

        $desc_extra_sentences[$i] =~ s/^(.*?) -//i;
        $desc_extra_sentences[$i] = norm($desc_extra_sentences[$i]);
      }

      if( my( $directors, $actors, $prodyear2, $country2 ) = (normUtf8($desc_extra_sentences[$i]) =~ /^di\s+(.*)\s+con\s+(.*)\s+(\d\d\d\d)\s+(.*?)/) )
      {
        $ce->{directors} = normUtf8(parse_person_list( $directors )) if normUtf8($directors) ne "AA VV"; # What is AA VV?
        $ce->{actors} = normUtf8(parse_person_list( $actors ));
        $ce->{production_date} = $prodyear2."-01-01";

        $desc_extra_sentences[$i] = "";
      }
      elsif( my( $directors2, $actors2 ) = (normUtf8($desc_extra_sentences[$i]) =~ /^di\s+(.*)\s+con\s+(.*)/) )
      {
        $ce->{directors} = normUtf8(parse_person_list( $directors2 )) if normUtf8($directors2) ne "AA VV"; # What is AA VV?
        $ce->{actors} = normUtf8(parse_person_list( $actors2 ));

        $desc_extra_sentences[$i] = "";
      }

      if( my( $actors2 ) = (normUtf8($desc_extra_sentences[$i]) =~ /^con\s*(.*)/) )
      {
        $ce->{actors} = normUtf8(parse_person_list( $actors2 ));
        $desc_extra_sentences[$i] = "";
      }

      if( my( $prodyear, $prodcountry ) = (norm($desc_extra_sentences[$i]) =~ /^(\d\d\d\d)\s+(.*?)$/) )
      {
        $ce->{production_date} = $prodyear."-01-01";
        $desc_extra_sentences[$i] = "";
      }
    }

    # Title stuff
    $ce->{title} =~ s/\^ Visione RAI//g;
    $ce->{title} = norm($ce->{title});

    # season, episode, episode title
    my($ep, $season, $episode, $dummy);

    # Episode and season (roman)
    ( $dummy, $ep ) = ($ce->{title} =~ /Ep(\.|)\s*(\d+)$/i );
    if(defined($ep) && !defined($ce->{episode})) {
      $ce->{episode} = sprintf( " . %d .", $ep-1 );
      $ce->{title} =~ s/- Ep(.*)$//gi;
    	$ce->{title} =~ s/Ep(.*)$//gi;
    	$ce->{title} = norm($ce->{title});
    	$ce->{title} =~ s/ serie$//gi;
    	$ce->{title} = norm($ce->{title});

    	# Season
    	my ( $original_title, $romanseason ) = ( $ce->{title} =~ /^(.*)\s+(.*)$/ );

      # Roman season found
      if(defined($romanseason) and isroman($romanseason)) {
        my $romanseason_arabic = arabic($romanseason);

        # Episode
      	my( $romanepisode ) = ($ce->{episode} =~ /.\s+(\d*)\s+./ );

        # Put it into episode field
        if(defined($romanseason_arabic) and defined($romanepisode)) {
          $ce->{episode} = sprintf( "%d . %d .", $romanseason_arabic-1, $romanepisode );

        	# Set original title
          $ce->{title} = norm($original_title);
        }
      }
    }

    # pt. ep
    ( $ep ) = ($title =~ /pt\.\s*(\d+)/ );
    if(defined($ep) && !defined($ce->{episode})) {
      $ce->{episode} = sprintf( " . %d .", $ep-1 );
      $ce->{title} =~ s/pt. (.*)$//g;
      $ce->{title} =~ s/pt.(.*)$//g;
    }

    # pt. ep
    ( $ep ) = ($title =~ /pt\s*(\d+)/ );
    if(defined($ep) && !defined($ce->{episode})) {
      $ce->{episode} = sprintf( " . %d .", $ep-1 );
      $ce->{title} =~ s/pt (.*)$//g;
      $ce->{title} =~ s/pt(.*)$//g;
    }

    # Seems buggy sometimes
    if(defined($ce->{episode})) {
        $ce->{program_type} = "series";
    }

    $ce->{title} = norm($ce->{title});
    $ce->{description} = join_text( @desc_extra_sentences ) if !defined($ce->{description}) or norm($ce->{description}) eq "";


	  p($time." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)$/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
      );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;


  my( $date ) = ( $objectname =~ /(\d+-\d+-\d+)$/ );
  my( $year, $month, $day ) = ($date =~ /^(\d+)-(\d+)-(\d+)$/ );


  my $url = sprintf( "http://www.rai.it/dl/portale/html/palinsesti/guidatv/static/%s_%s_%s_%s.html",
                     $chd->{grabber_info},
                     $year, $month, $day);


  return( $url, undef );
}

# Split a string into individual sentences.
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

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-ZÅÄÖa-zåäö0-9])/$1;;$2/g;

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

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

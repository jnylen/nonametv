package NonameTV::Importer::MediasetIT;

use strict;
use warnings;

=pod

Imports data for Mediaset channels

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Data::Dumper;
use Roman;

use NonameTV qw/ParseXmlFile norm AddCategory AddCountry MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Rome" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "MediasetIT: $chd->{xmltvid}: Processing XML $file" );

  my $doc = ParseXmlFile($file);

  # Find all paragraphs.
  my $ns = $doc->find( "//Record" );

  if( $ns->size() == 0 ) {
    error "No Programs found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
      my $date  = ParseDate($progs->findvalue( 'Data' ));

      # Date
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "07:00" );
        $currdate = $date;

        progress("MediasetIT: Date is: $date");
      }

      my $title_prod = norm($progs->findvalue( 'TitoloProd' ));
      my $title_full = norm($progs->findvalue( 'Titolo' ));
      my $title_sub = norm($progs->findvalue( 'TitoloElem' ));
      my $title = $title_prod || $title_full;
      my $time  = $progs->findvalue( 'Ora' );
      my $type  = $progs->findvalue( 'Tipo' );
      my $year  = $progs->findvalue( 'Anno' );
      my $genre  = $progs->findvalue( 'Genere' );

      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $time,
      };

      # Genre
      if( $type ){
          my($program_type, $category ) = $ds->LookupCat( 'MediasetIT', $type );
          AddCategory( $ce, $program_type, $category );
      }

      if( $genre ){
          my($program_type2, $category2 ) = $ds->LookupCat( 'MediasetIT_genre', $genre );
          AddCategory( $ce, undef, $category2 );
      }

      # Metadata
      my $note = norm($progs->findvalue( 'Note' ));
      my $episodenum2 = undef;
      my $seasonnum2 = undef;
      my($seasonnum, $episodenum, $subtitle, $cast, $duration, $director, $prodyear, $country, $synopsis, $dummy, $genre2);
      my @notes = (split_text( $note ), "");
      for( my $i2=0; $i2<scalar(@notes); $i2++ )
      {
        if( ( $episodenum, $subtitle ) = ($notes[$i2] =~ /^Ep\. (\d+) (.*?)$/ ) )
        {
          $episodenum2 = $episodenum;
          $ce->{subtitle} = norm($subtitle);
          $notes[$i2] = "";
        } elsif( ( $episodenum, $subtitle ) = ($notes[$i2] =~ /^Ep\. (\d+)-(.*?)$/ ) )
        {
          $episodenum2 = $episodenum;
          $ce->{subtitle} = norm($subtitle);
          $notes[$i2] = "";
        } elsif( ( $cast, $director ) = ($notes[$i2] =~ /^Cast\: (.*?)\. Regia\: (.*?)$/ ) ) {
          $director =~ s/SIT COM (\d+)$//i;
          $director =~ s/SIT COM (\d+)'$//i;
          $ce->{directors} = parse_person_list( $director );
          $ce->{actors} = parse_person_list( $cast );
          $notes[$i2] = "";
        } elsif( ( $cast, $genre2, $duration, $dummy ) = ($notes[$i2] =~ /^Cast\: (.*?)\. (.*?) (\d+)(|')$/ ) ) {
          $ce->{actors} = parse_person_list( $cast );
          $notes[$i2] = "";
        } elsif( ( $cast ) = ($notes[$i2] =~ /^Cast\: (.*?)$/ ) ) {
          $ce->{actors} = parse_person_list( $cast );
          $notes[$i2] = "";
        } elsif( ( $director ) = ($notes[$i2] =~ /^Regia\: (.*?)$/ ) ) {
          $ce->{directors} = parse_person_list( $director );
          $notes[$i2] = "";
        } elsif( ( $country, $prodyear, $dummy ) = ($notes[$i2] =~ /^(.*?), (\d\d\d\d)(|\.)$/ ) ) {
          $notes[$i2] = "";
        } elsif( ( $seasonnum, $episodenum, $subtitle ) = ($notes[$i2] =~ /^Serie (\d+), ep\. (\d+) (.*?)$/i ) ) {
          $episodenum2 = $episodenum;
          $seasonnum2 = $seasonnum;
          #$ce->{subtitle} = norm($subtitle);
          $notes[$i2] = "";
        } elsif( ( $seasonnum, $episodenum, $subtitle ) = ($notes[$i2] =~ /^Stagione (\d+), ep\. (\d+) (.*?)$/i ) ) {
          $episodenum2 = $episodenum;
          $seasonnum2 = $seasonnum;
          #$ce->{subtitle} = norm($subtitle);
          $notes[$i2] = "";
        } elsif( ( $seasonnum, $episodenum, $subtitle ) = ($notes[$i2] =~ /^Stagione (\d+), ep\. (\d+) (.*?)/i ) ) {
          $episodenum2 = $episodenum;
          $seasonnum2 = $seasonnum;
          #$ce->{subtitle} = norm($subtitle);
          #$notes[$i2] = "";
        } elsif( ( $genre, $duration ) = ($notes[$i2] =~ /^(.*?) (\d+)\'$/ ) ) {
          $notes[$i2] = "";
        } elsif( ( $genre, $duration ) = ($notes[$i2] =~ /^(.*?) (\d+)$/ ) ) {
          print Dumper($genre, $duration);
          $notes[$i2] = "";
        }
      }
      $ce->{description} = join_text( @notes );
      #print Dumper(@notes);


      # Year
      if( defined($year) and $year =~ /(\d\d\d\d)/ )
      {
        $ce->{production_date} = "$1-01-01";
      }

      # Episode info in xmltv-format
      ## Grab from title
      if((defined($ce->{program_type}) and $ce->{program_type} ne "movie") and!defined($seasonnum2) and my($romantitle, $romanseason) = ($ce->{title} =~ /^(.*)\s+([IXVL]+)$/i)) {
        if(defined($romanseason) and isroman(norm($romanseason))) {
          $seasonnum2 = arabic($romanseason);
          $ce->{title} = norm($romantitle);
        }
      }

      if( defined($episodenum2) and defined($seasonnum2) )
      {
        $ce->{episode} = sprintf( "%d . %d .", $seasonnum2-1, $episodenum2-1 );
      }
      elsif( defined($episodenum2) )
      {
        $ce->{episode} = sprintf( ". %d .", $episodenum2-1 );
      }

      # Fix title
      $ce->{title} =~ s/\-$//;
      $ce->{title} = norm($ce->{title});

      #print Dumper($ce);

      $dsh->AddProgramme( $ce );

      progress( "MediasetIT: $chd->{xmltvid}: $time - $title" );
  }

  $dsh->EndBatch( 1 );

  return 1;
}


sub ParseDate {
  my( $text ) = @_;
  my( $dayname, $day, $monthname, $year );
  my $month;

  if( ( $day, $month, $year ) = ( $text =~ /^(\d+)\-(\d+)\-(\d\d\d\d)$/ ) ) { # format '07.09.2017'
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
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

  # Replace  - with ;;
  $t =~ s/\s+-\s+/;;/g;

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
  #$t =~ s/([\.\!\?])\s+([\(A-Z���])/$1;;$2/g;

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

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s+$//;
    s/^\S*\s+(\d\d\d\d)$//; # USA 1996
    s/\.$//;
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;

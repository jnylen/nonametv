package NonameTV::Importer::Svt_PS;

use strict;
use warnings;

=pod

Imports data for SVT-channels. Sent by SVT via FTP in XML-Format

Every day is handled as a seperate batch,
The files get sent everyday for one day

Example for 2011-08-25:
2011-08-25

Channels: SVT1, SVT1 (both cast in seperate HD channels aswell,
but the same schedule), SVTB, 24, SVTK (Kunskapskanalen).

=cut

use utf8;

use DateTime;
use XML::LibXML;
use XML::LibXML::XPathContext;
use IO::Scalar;
use Data::Dumper;
use Text::Unidecode;
use File::Slurp;
use Encode;

use NonameTV qw/ParseXml norm normLatin1 normUtf8 AddCategory MonthNumber ParseDescCatSwe AddCategory/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

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
    print("Importing $file\n");
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my( $service_id ) = norm($chd->{grabber_info});
  my $currdate = "x";

  # Perl don't seem to be able to have multiple namespaces with different urls
  my $cref=`cat \"$file\"`;
  $cref =~ s|http://common.tv.se/material/v4_0|http://common.tv.se/content/v4_0|g;
  $cref =~ s|http://common.tv.se/event/v4_0|http://common.tv.se/content/v4_0|g;

  # Parse it
  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if( not defined( $doc ) ) {
    error( "Svt_PS: $file: Failed to parse xml" );
    return;
  }

  # Load it with namespaces
  my $xpc = XML::LibXML::XPathContext->new( $doc );
  $xpc->registerNs('v4',  'http://common.tv.se/schedule/v4_0');
  $xpc->registerNs('v41',  'http://common.tv.se/content/v4_0');

  # Material
  my $mis = $xpc->findnodes( ".//v41:material" );
  my %materials;

  if( $mis->size() == 0 ) {
      error( "Svt_PS: No Materials found" ) ;
      return;
  }

  foreach my $mi ($mis->get_nodelist) {
    my $mid = $mi->findvalue( 'v41:materialId' );

    my $m = {
      aspectRatio     => norm($mi->findvalue( 'v41:aspectRatio' )),
      videoFormat     => norm($mi->findvalue( 'v41:videoFormat' )),
      audio_lang      => norm($mi->findvalue( 'v41:audioList/v41:format/@language' )),
      audio_format    => norm($mi->findvalue( 'v41:audioList/v41:format' )),
    };

    $materials{$mid} = $m;
  }


  # Content
  my $cis = $xpc->findnodes( ".//v41:content" );
  my %contents;

  if( $cis->size() == 0 ) {
      error( "Svt_PS: No Contents found" ) ;
      return;
  }

  foreach my $ci ($cis->get_nodelist) {
    my $cid = $ci->findvalue( 'v41:contentId' );

    my $c = {
      seasonNumber      => norm($ci->findvalue( 'v41:seasonNumber' )),
      episodeNumber     => norm($ci->findvalue( 'v41:episodeNumber' )),
      numberOfEpisodes  => norm($ci->findvalue( 'v41:numberOfEpisodes' )),
      productionYear    => norm($ci->findvalue( 'v41:productionYear' )),
      countryOfOrigin   => join("||", ParseIt($ci, 'v41:countryOfOriginList/v41:country')),
      title             => norm($ci->findvalue( 'v41:titleList/v41:title[@type="season"]' )),
      description_med   => norm($ci->findvalue( 'v41:descriptionList/v41:description[@length="medium"]' )),
      keywords          => join("||", ParseIt($ci, 'v41:categoryList/v41:category/v41:treeNode')),
    };

    $contents{$cid} = $c;
  }

  ## Batch
  my ($year, $month, $day) = ($file =~ /(\d\d\d\d)(\d\d)(\d\d)/);

  if(!defined $year) {
      error( "$file: $chd->{xmltvid}: Failure to get year from filename" ) ;
      return;
  }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$month . "-".$day;

  $dsh->StartBatch( $batchid , $chd->{id} );

  # Programmes
  my $rows = $xpc->findnodes( './/v4:eventList/v41:event' );

  if( $rows->size() == 0 ) {
      error( "Svt_PS: No Events found" ) ;
      return;
  }

  foreach my $event ($rows->get_nodelist) {
    $xpc->setContextNode( $event );

    my $channel_ref = $xpc->findvalue( 'v41:channelId' );
    
    # Needs to be the correct channel.
    if($channel_ref ne $service_id) {
        next;
    }

    # Events - Date
    my $start   = $self->create_dt($xpc->findvalue( 'v41:timeList/v41:time/v41:startTime' ));
    my $end     = $self->create_dt($xpc->findvalue( 'v41:timeList/v41:time/v41:endTime' ));
    my $date    = $start->ymd("-");

    if($date ne $currdate ) {
     if( $currdate ne "x" ) {
	#	$dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      #$dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

     progress("Svt_PS: Date is: $date");
    }

    # Events
    my $is_live     = $xpc->findvalue( 'v41:live' );
    my $is_rerun    = $xpc->findvalue( 'v41:rerun' );
    my $content_id  = $xpc->findvalue( 'v41:contentIdRef' );
    my $material_id = $xpc->findvalue( 'v41:materialIdRef' );

    # Materials
    my $md         = $materials{$material_id};
    my $video      = $md->{aspectRatio};
    my $audio      = $md->{audio_format};

    # Content
    my $cd         = $contents{$content_id};
    my $title      = $cd->{title};
    my $keywords   = $cd->{keywords};
    my $desc       = $cd->{description_med};
    my $season     = $cd->{seasonNumber};
    my $episode    = $cd->{episodeNumber};
    my $of_episode = $cd->{numberOfEpisodes};
    my $countries  = $cd->{countryOfOrigin};
    my $prodyear   = $cd->{productionYear};


    my $ce = {
        channel_id   => $chd->{id},
        title        => norm($title),
        start_time   => $start->hms(":"),
        end_time     => $end->hms(":"),
    };

    # Production year
    if( defined( $prodyear ) and ($prodyear =~ /(\d\d\d\d)/) )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # Formats
    ## Aspect
    if(defined($video) and $video eq "16:9")
    {
        $ce->{aspect} = "16:9";
    } elsif(defined($video) and $video eq "4:3") {
        $ce->{aspect} = "4:3";
    }

    # 5.1
    if(defined($audio) and $audio eq "stereo")
    {
        $ce->{stereo} = "stereo";
    }

    # Texts 
    my @sentences = (split_text( $desc ), "");

    for( my $i=0; $i<scalar(@sentences); $i++ )
    {
        # Säsong x
        if( my( $seasontextnum ) = ($sentences[$i] =~ /^Säsong (\d+)./ ) )
	    {
	      $season = $seasontextnum;

	      # Only remove sentence if it could find a season
	      if($season ne "") {
	      	$sentences[$i] = "";
	      }
	    }
        # Sjätte säsongen
        elsif( my( $seasontext ) = ($sentences[$i] =~ /\b(\S+)\b säsongen\.$/ ) )
	    {
	      $seasontext =~ s/ och sista//g;
	      $seasontext = lc($seasontext);
	      $seasontext = SeasonText($seasontext);

          if($seasontext ne "") {
            $season = $seasontext;
          }

	      # Only remove sentence if it could find a season
	      if($season ne "") {
	      	$sentences[$i] = "";
	      }
	    }
        # (original titel)
        elsif( my( $originaltitle ) = ($sentences[$i] =~ /^\((.*)\)\.$/ ) )
        {
            $ce->{original_title} = norm($originaltitle) if norm($originaltitle) ne $ce->{title};
            $sentences[$i] = "";
        }
        # Del x
        elsif( $sentences[$i] =~ /Del\s+\d+\.*/ )
        {
            # If this program has an episode-number, it is by definition
            # a series (?). Svt often miscategorize series as movie.
            $ce->{program_type} = 'series';

            my( $ep, $eps, $name, $episode, $dummy );
            # Del 2 av 3: Pilot (episodename)
            ( $ce->{subtitle} ) = ($sentences[$i] =~ /:\s*(.+)\./);

            # norm2
            $ce->{subtitle} = norm2($ce->{subtitle});

            $sentences[$i] = "";
        }
        # Regi: *
        elsif( my( $directors ) = ($sentences[$i] =~ /^Regi:\s*(.*)/) )
        {
            $ce->{directors} = parse_person_list( $directors );
            $sentences[$i] = "";
        }
        # I rollerna: *
        elsif( my( $actors ) = ($sentences[$i] =~ /^I rollerna:\s*(.*)/ ) )
        {
            $ce->{actors} = parse_person_list( $actors );
            $sentences[$i] = "";
        }
        # Övriga medverkande: *
        elsif( my( $actors2 ) = ($sentences[$i] =~ /^Övriga\s+medverkande:\s*(.*)/ ) )
        {
            $ce->{actors} = parse_person_list( $actors2 );
            $sentences[$i] = "";
        }
        # Medverkande: *
        elsif( my( $actors3 ) = ($sentences[$i] =~ /^Medverkande:\s*(.*)/ ) )
        {
            $ce->{actors} = parse_person_list( $actors3 );
            $sentences[$i] = "";
        }
        # Kommentator: *
        elsif( my( $commentators ) = ($sentences[$i] =~ /^Kommentator:\s*(.*)/ ) )
        {
            $ce->{commentators} = parse_person_list( $commentators );
            $sentences[$i] = "";
        }
        # Kommentatorer: *
        elsif( my( $commentators2 ) = ($sentences[$i] =~ /^Kommentatorer:\s*(.*)/ ) )
        {
            $ce->{commentators} = parse_person_list( $commentators2 );
            $sentences[$i] = "";
        }
        # Programledare: *
        elsif( my( $presenters ) = ($sentences[$i] =~ /^Programledare:\s*(.*)/ ) )
        {
            $ce->{presenters} = parse_person_list( $presenters );
            $sentences[$i] = "";
        }
        # Gästartist: *
        elsif( my( $guestartist ) = ($sentences[$i] =~ /^Gästartist:\s*(.*)/ ) )
        {
            $ce->{guests} = parse_person_list( $guestartist );
            $sentences[$i] = "";
        }
        # Kvällens gäster: *
        elsif( my( $guests ) = ($sentences[$i] =~ /^Kvällens\s+gäster:\s*(.*)/ ) )
        {
            $ce->{guests} = parse_person_list( $guests );
            $sentences[$i] = "";
        }
        # Gäster ikväll: *
        elsif( my( $guests2 ) = ($sentences[$i] =~ /^Gäster\s+ikväll:\s*(.*)/ ) )
        {
            $ce->{guests} = parse_person_list( $guests2 );
            $sentences[$i] = "";
        }
        # HD
        elsif( my( $hd ) = ($sentences[$i] =~ /^HD\.$/ ) )
        {
            $ce->{quality} = "HDTV";
            $sentences[$i] = "";
        }
        # Sänds med 5.1 ljud
        elsif( my( $dolby ) = ($sentences[$i] =~ /^Sänds med 5\.1 ljud\.$/ ) )
        {
            $ce->{stereo} = "dolby digital";
            $sentences[$i] = "";
        }
        # Från xxxx
        elsif( my( $from_prod_year ) = ($sentences[$i] =~ /^Från (\d\d\d\d)\.$/ ) )
        {
            $sentences[$i] = "";
        }
    }

    # Remove titles which can't be matched if they are in there
    $ce->{title} =~ s/^(Filmkluben)\://i;
    $ce->{title} = norm($ce->{title});

    $ce->{description} = join_text( @sentences );
    
    # Episode info in xmltv-format
    if( ($episode ne "0" and $episode ne "") and ( $of_episode ne "0" and $of_episode ne "") and ( $season ne "0" and $season ne "") )
    {
        $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $of_episode );
    }
    elsif( ($episode ne "0" and $episode ne "") and ( $season ne "0" and $season ne "") )
    {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }
    elsif( ($episode ne "0" and $episode ne "") and ( $of_episode ne "0" and $of_episode ne "") )
    {
        if( defined( $prodyear ) and ($prodyear =~ /(\d\d\d\d)/) ) {
      		$ce->{episode} = sprintf( "%d . %d/%d .", $1-1, $episode-1, $of_episode );
      	} else {
        	$ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
        }
    }
    elsif( $episode ne "0" and $episode ne "" )
    {
      	if( defined( $prodyear ) and ($prodyear =~ /(\d\d\d\d)/) ) {
      		$ce->{episode} = sprintf( "%d . %d .", $1-1, $episode-1 );
      	} else {
      		$ce->{episode} = sprintf( ". %d .", $episode-1 );
        }

    }

    # Remove if season = 0, episode 1, of_episode 1 - it's a one episode only programme
    if(($episode eq "1") and ( $of_episode eq "1") and ( $season eq "0")) {
        delete($ce->{episode});
    }

    # News programmes shouldn't have episodeinfo
    if($ce->{title} =~ /^(Aktuellt|24 Vision|Rapport|Regionala nyheter|Sportnytt|Kulturnyheterna|Uutiset|Oddasat|Nyhetstecken|SVT Forum|Sydnytt|Värmlandsnytt|Nordnytt|Mittnytt|Gävledala|Tvärsnytt|Östnytt|Smålandsnytt|Västnytt|ABC)$/i) {
        delete($ce->{episode});
    }

    # Live?
    if($is_live eq "true") {
        $ce->{live} = "1";
    } else {
        $ce->{live} = "0";
    }

    # Keywords / Genres
    if(defined($keywords)) {
        foreach my $keyword (split(/\|\|/, $keywords)) {
            my ( $pty, $cat ) = $ds->LookupCat( 'Svt_ps', $keyword );
            AddCategory( $ce, $pty, $cat );
        }
    }

    #my ( $program_type, $category ) = ParseDescCatSwe( $desc );
  	#AddCategory( $ce, $program_type, $category );

    progress( "Svt_PS: $chd->{xmltvid}: $start - $title" );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );

  my( $year, $month, $day ) = split( '-', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );


  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'UTC',
                          );

  #$dt->set_time_zone( "Europe/Stockholm" );

  return $dt;
}

# From SVT_WEB

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
    s/^\.$//;
  }

  return join( ";", grep( /\S/, @persons ) );
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

sub SeasonText {
  my( $seasonname ) = @_;

  my( @seasons_1, @seasons_2 );
  @seasons_1 = qw/första andra tredje fjärde femte sjätte/;
  @seasons_2 = qw//;

  my %seasons = ();

  for( my $i = 0; $i < scalar(@seasons_1); $i++ ){
    $seasons{$seasons_1[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@seasons_2); $i++ ){
    $seasons{$seasons_2[$i]} = $i+1;
  }

  my $season = $seasons{$seasonname};
  my $null = "";

  return $season||$null;
}

sub norm2 {
  my( $str ) = @_;

  return "" if not defined( $str );

  #$str =~ s/ï¿½/ä/;
  #$str =~ s/ï¿½/å/;

  #return $str;

  return normUtf8($str);
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

# e.g. ParseIt( $sc, './programm//besetzung/darsteller' );
# e.g. ParseIt( $sc, './programm//stab/person[funktion=buch]' );
sub ParseIt
{
  my( $root, $xpath) = @_;

  my @array;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    push( @array, $node->textContent );
  }

  return @array;
}

1;

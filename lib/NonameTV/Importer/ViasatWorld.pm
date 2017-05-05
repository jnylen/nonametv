package NonameTV::Importer::ViasatWorld;

use strict;
use warnings;

=pod

Importer for data from Viasat World (Owner of the old MTG PayTV Channels).
The data is a day-seperated feed of programmes.
<programtable>
	<day date="2012-09-10>
		<program>
		</program>
	</day>
</programtable>
=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory AddCountry/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseMonthly;

use base 'NonameTV::Importer::BaseMonthly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MaxMonths} = 2 unless defined $self->{MaxMonths};
    $self->{Timezone} = "CET" unless defined $self->{Timezone};

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, $self->{Timezone} );

    # use augment
    $self->{datastore}->{augment} = 1;

    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month ) = ( $objectname =~ /(\d+)-(\d+)$/ );
  my $pad_len = 2;
  $month = sprintf("%0${pad_len}d", $month);
  my( $directory, $name ) = split( /:/, $chd->{grabber_info} );

  my $url = $self->{UrlRoot} . $directory . $year . '-' . $month.'-'. $name .'-' . $self->{Timezone} . '.xml';

  return( $url, undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref =~ '<!--' ) {
    return "404 not found";
  }
  elsif( $$cref eq '' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}


sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s|\?>|\?>\n|g;

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );
  my $currdate = "x";

  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//day" );

  if( $ns->size() == 0 ) {
    f "No days found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
  	# Date
    my( $date ) = norm( $sched_date->findvalue( '@date' ) );

    if( $currdate ne "x" ){
  		# save last day if we have it in memory
  		#FlushDayData( $xmltvid, $dsh , @ces );
  		#$dsh->EndBatch( 1 );
  		#@ces = ();
  	}

  	$dsh->StartDate( $date , "06:00" );
  	$currdate = $date;

  	progress("ViasatWorld: $xmltvid: Date is $date");

    my $ns2 = $sched_date->find('program');
    foreach my $emission ($ns2->get_nodelist) {

      # General stuff
      my $start_time = $emission->findvalue( 'startTime' );
      my $other_name = $emission->findvalue( 'name' );
      my $original_name = $emission->findvalue( 'orgName' );
      my $name = $other_name || $original_name;
      $name =~ s/#//g; # crashes the whole importer
      $name =~ s/(HD)//g; # remove category_

      # Category and genre
      my $category = $emission->findvalue( 'category' ); # category_series, category_movie, category_news
      $category =~ s/category_//g; # remove category_
      my $genre = $emission->findvalue( 'genre' );

      # Description
      my $desc_episode = $emission->findvalue( 'synopsisThisEpisode' );
      my $desc_series = $emission->findvalue( 'synopsis' );
      my $logline = $emission->findvalue( 'logline' );


      my $desc = $desc_episode || $desc_series || $logline;

      # Season and episode
      my $episode = $emission->findvalue( 'episode' );
      my $season = $emission->findvalue( 'season' );

      # Extra stuff
      my $prodyear = $emission->findvalue( 'productionYear' );
      my $widescreen = $emission->findvalue( 'wideScreen' );
      my $bline = $emission->findvalue( 'bline' );
      my $lead  = $emission->findvalue( 'lead' );
      my $rerun = $emission->findvalue( 'rerun' );
      my $live  = $emission->findvalue( 'live' );

      # Actors and directors
      my @actors;
      my @directors;

      my $ns3 = $emission->find( './/castMember' );
      foreach my $act ($ns3->get_nodelist)
      {
        push @actors, $act->to_literal;
      }

      my @countries;
        my $ns4 = $emission->find( './/country' );
        foreach my $con ($ns4->get_nodelist)
      {
        my ( $c ) = $self->{datastore}->LookupCountry( "Viasat", $con->to_literal );
        push @countries, $c if defined $c;
      }

      my $ce = {
          title       => norm($name),
          description => norm($desc),
          start_time  => $start_time,
        };

        my $extra = {};
        $extra->{descriptions} = [];
        $extra->{qualifiers} = [];


        # Send back original swedish title
        if(norm($name) ne norm($original_name)) {
          $ce->{original_title} = norm($original_name);
        }

        # Actors
        if( scalar( @actors ) > 0 )
      {
          $ce->{actors} = join ";", @actors;
      }

        if( scalar( @countries ) > 0 )
      {
          $ce->{country} = join "/", @countries;
      }

      # prod year
      if(defined($prodyear) and $prodyear ne "" and $prodyear =~ /(\d\d\d\d)/)
      {
        $ce->{production_date} = "$1-01-01";
      } elsif(defined($bline) and $bline ne "" and $bline =~ /(\d\d\d\d)/) {
          $ce->{production_date} = "$1-01-01";
        }

      # Find aspect-info ( they dont appear to actually use this correctly )
      if( $widescreen eq "TRUE" )
      {
        $ce->{aspect} = "16:9";
        #push $extra->{qualifiers}, "widescreen";
      }
      else
      {
        $ce->{aspect} = "4:3";
        #push $extra->{qualifiers}, "smallscreen";
      }

      # Find rerun-info
      if( $rerun eq "TRUE" )
      {
        $ce->{new} = "0";
        push $extra->{qualifiers}, "repeat";
      }
      else
      {
        $ce->{new} = "1";
        push $extra->{qualifiers}, "new";
      }

      # Find live-info
      if( $live eq "TRUE" or $lead eq "LIVE" or $lead eq "LIVE:" )
      {
        $ce->{live} = "1";
        push $extra->{qualifiers}, "live";
      }
      else
      {
        $ce->{live} = "0";
      }

      if( $emission->findvalue( 'director' ) ) {
        my $dirs = norm($emission->findvalue( 'director' ));
        $dirs =~ s/ & /, /g;
        $ce->{directors} = parse_person_list($dirs);

        # Movie?
        if($season eq "0" and $episode eq "0") {
          $ce->{program_type} = "movie";
        }
      }


      # Episodes
      if($episode and $episode ne "0") {
        if($season and $season ne "0") {
          $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
        } else {
          $ce->{episode} = sprintf( " . %d . ", $episode-1 );
        }
      }

      # Genres and category
      my( $pty, $cat );
      if(defined($genre) and $genre and $genre ne "") {
        my @genres = split("/", $genre);
        my @cats;
        foreach my $node ( @genres ) {
          my ( $type, $categ ) = $self->{datastore}->LookupCat( "ViasatWorld_genre", $node );
          push @cats, $categ if defined $categ;
        }
        my $cat = join "/", @cats;
        AddCategory( $ce, $pty, $cat );
      }

      if(defined($category) and $category and $category ne "") {
          ( $pty, $cat ) = $ds->LookupCat( 'ViasatWorld_category', $category );
          AddCategory( $ce, $pty, $cat );
      }

      # Images
      my $imgs = $pgm->find( './/images/image' );
      foreach my $item ($imgs->get_nodelist)
      {
          push $extra->{images}, { url => $item->findvalue( 'original/@src' ), type => undef, title => undef, copyright => norm($item->findvalue( '@credits' )), source => "Viasat World" };
      }

      $ce->{extra} = $extra;

      progress( "ViasatWorld: $chd->{xmltvid}: $start_time - $name" );
      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;

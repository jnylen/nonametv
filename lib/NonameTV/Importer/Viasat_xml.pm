package NonameTV::Importer::Viasat_xml;

use strict;
use warnings;

=pod

Importer for data from Viasat.
The data is a day-seperated feed of programmes.
<programtable>
	<day date="2012-09-10>
		<program>
		</program>
	</day>
</programtable>

Use this instead of Viasat.pm as the TAB-seperated is
a dumb idea. If an employee of MTG drops a tab in the desc
it think its a new field.
=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;
use Try::Tiny;

use NonameTV qw/ParseXml norm AddCategory AddCountry/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinWeeks} = 0 unless defined $self->{MinWeeks};
    $self->{MaxWeeks} = 4 unless defined $self->{MaxWeeks};
    $self->{Timezone} = "Europe/Stockholm" unless defined $self->{Timezone};

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, $self->{Timezone} );

    # use augment
    $self->{datastore}->{augment} = 1;

    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $country_tld, $year, $week ) = ( $objectname =~ /\.(\w\w)_(\d+)-(\d+)$/ );
  my $pad_len = 2;
  $week = sprintf("%0${pad_len}d", $week);
  $country_tld =~ s/^ee$/lt/i;

  my $url = 'http://' . $country_tld . '.press.viasat.tv/press/cm/listings/'. $chd->{grabber_info} . $year . '-' . $week.'.xml';
  print("url: $url\n");

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

  $$cref =~ s| xmlns="http://www.mtg.se/xml/weeklisting"||g;
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

	#my $batch_id = "${xmltvid}_" . $date;
	#$dsh->StartBatch( $batch_id, $channel_id );
	$dsh->StartDate( $date , "00:00" );
	$currdate = $date;

	progress("Viasat: $xmltvid: Date is $date");
  my $lastitem = 0;

    # Programmes
    my $ns2 = $sched_date->find('program');
    foreach my $emission ($ns2->get_nodelist) {
      next if $lastitem == 1;
      # General stuff
      my $start_time = $emission->findvalue( 'startTime' );
      my $other_name = $emission->findvalue( 'name' );
      my $original_name = $emission->findvalue( 'orgName' );
      my $name = $other_name || $original_name;
      $name =~ s/#//g; # crashes the whole importer
      $name =~ s/\(HD\)//g; # remove category_
      $name =~ s/\(m\)//g; # remove (m)

      # # End of airtime
      if( ($name =~ /^HEAD\s+..D/) or ($name =~ /^Programmas beigas/) or ($name =~ /^P.\s+GENSYN/) or ($name =~ /^OPHOLD I SENDEFLADE/)
          or ($name eq "GODNAT") or ($name eq "END") or ($name =~ /^Programos pabaiga/) or ($name =~ /^S.ndningsuppeh.ll/ or ($name =~ /^L.hetystauko$/i)) )
      {
      	$name = "end-of-transmission";
        $lastitem = 1;
      }


      # Category and genre
      my $category = $emission->findvalue( 'category' ); # category_series, category_movie, category_news
      $category =~ s/category_//g; # remove category_
      my $genre = $emission->findvalue( 'genre' );

      # Description
      my $desc_episode = $emission->findvalue( 'synopsisThisEpisode' );
      my $desc_series = $emission->findvalue( 'synopsis' );
      my $desc_logline = $emission->findvalue( 'logline' );

      my ($eps, $episode2, $season2, $episode3);

      if($desc_episode =~ /Del\s+(\d+):(\d+)/i) {
        ( $episode3, $eps ) = ($desc_episode =~ /Del\s+(\d+):(\d+)/i );
        $desc_episode =~ s/Del (\d+):(\d+)//gi;
      }

      if($desc_logline =~ /\(S(\d+), Ep(\d+)\)$/i) {
        ( $season2, $episode2 ) = ($desc_logline =~ /\(S(\d+), Ep(\d+)\)$/i );
        $desc_logline =~ s/\(S(\d+), Ep(\d+)\)$//gi;
      }

      # Sometimes episode3 is correct rather than episode2
      if(defined($episode3)) {
        if(defined($episode2)) {
          # Ep2 is defined
          if($episode2 > $episode3) {
            $episode2 = $episode3;
          }
        } else {
          # Ep2 isn't defined
          $episode2 = $episode3;
        }
      }


      my $desc = $desc_episode || $desc_series || $desc_logline;
      $desc =~ s/\s+\.$//;
      $desc =~ s/\?\./\?/g;

      # Season and episode
      my $episode = $emission->findvalue( 'episode' );
      my $season = $emission->findvalue( 'season' );

      # Remove from title
      if(defined($season) and $season ne "" and $category eq "series") {
        $name =~ s/- s(.*)son $season$//;
        $name =~ s/ \(s(.*?)son $season\)$//;
        $name =~ s/$season$//;
        $name = norm($name);

        # Depotjægerne has seasonnumepisodenum
        if($name =~ /^Depotj.*gerne$/i or $name =~ /^Depotj.*gerne fra Texas$/i or $name =~ /^Depotj.*gerne: New York$/i) {
          if(defined($episode) and $episode ne "" and $episode =~ /^(\d\d\d)$/) {
            $episode =~ s/^$season//;
          } elsif(defined($episode2) and $episode2 ne "" and $episode2 =~ /^(\d\d\d)$/) {
            $episode2 =~ s/^$season//;
          }
        }
      }

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
        my $acts = $act->to_literal;
        $acts =~ s|^(.*?) - (.*?)$|$1 ($2)|;
  	  	push @actors, $acts;
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
      $extra->{sport} = {};
      $extra->{descriptions} = [];
      $extra->{external} = { type => "viasat", id => $emission->findvalue( 'uniqueId' )};
      $extra->{qualifiers} = [];

      # descriptions
      if($bline and defined($bline) and norm($bline) ne "") {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($bline), type => "bline" };
      }
      if($desc_series and defined($desc_series) and norm($desc_series) ne "") {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($desc_series), type => "series" };
      }
      if($desc_logline and defined($desc_logline) and norm($desc_logline) ne "") {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($desc_logline), type => "logline" };
      }
      if($desc_episode and defined($desc_episode) and norm($desc_episode) ne "") {
        push @{$extra->{descriptions}}, { lang => $chd->{sched_lang}, text => norm($desc_episode), type => "episode" };
      }


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
  	  if( $widescreen eq "true" )
  	  {
  	    $ce->{aspect} = "16:9";
        #push @{$extra->{qualifiers}}, "widescreen";
  	  }
  	  else
  	  {
  	    $ce->{aspect} = "4:3";
        #push @{$extra->{qualifiers}}, "smallscreen";
  	  }

  	  # Find rerun-info
  	  if( $rerun eq "true" )
  	  {
  	    $ce->{new} = "0";
        push @{$extra->{qualifiers}}, "repeat";
  	  }
  	  else
  	  {
  	    $ce->{new} = "1";
        push @{$extra->{qualifiers}}, "new";
  	  }

  	  # Find live-info
  	  if( $live eq "true" or $lead eq "LIVE" or $lead eq "LIVE:" or $lead eq "DIREKTE:" )
  	  {
  	    $ce->{live} = "1";
        push @{$extra->{qualifiers}}, "live";
  	  }
  	  else
  	  {
  	    $ce->{live} = "0";
  	  }

  	  if( $emission->findvalue( 'director' ) ) {
  	    my $dirs = norm($emission->findvalue( 'director' ));
  	    $dirs =~ s/ & /, /g;
  	    $ce->{directors} = parse_person_list($dirs);
  	  }

      # Episodes
      if($episode2 and $episode2 ne "") {
      	if($season) {
      		if($eps and $eps ne "") {
      			$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode2-1, $eps );
      		} else {
      			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode2-1 );
      		}
      	}elsif($eps and $eps ne "") {
      		$ce->{episode} = sprintf( " . %d/%d . ", $episode2-1, $eps );
      	} else {
      		$ce->{episode} = sprintf( " . %d . ", $episode2-1 );
      	}
      } elsif($episode) {
      	if($season) {
      		if($eps and $eps ne "") {
      			$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $eps );
      		} else {
      			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      		}
      	}elsif($eps and $eps ne "") {
      		$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $eps );
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
          my ( $type, $categ ) = $self->{datastore}->LookupCat( "Viasat_genre", $node );
          push @cats, $categ if defined $categ;
        }
        my $cat = join "/", @cats;
        AddCategory( $ce, $pty, $cat );
  	  }

  	  if(defined($category) and $category and $category ne "") {
  	    ( $pty, $cat ) = $ds->LookupCat( 'Viasat_category', $category );
  	  	AddCategory( $ce, $pty, $cat );
  	  }

      # Sometimes they fuck up
      if($bline eq "National Football League") {
        $ce->{program_type} = "sports";
      }

      # sports
      if($ce->{program_type} eq "sports" and ($other_name =~ /^(.*?)\: (.*?)$/)) {
        my $league_gotten = 0;
        my ($game, $teams_cat) = ($original_name =~ /^(.*?)\: (.*?)$/);
        # $1 = League or sport
        # $2 = Teams or league
        # League name can sometimes be in BLINE
        my $one = $1;
        my $two = $2;
        my($league3, $game3 );

        ## Danish
        if($chd->{xmltvid} =~ /\.dk$/i) {
          # These are not real sports games
          if($bline =~ /(H.jdepunkter|Optakt|Magasin)/i) {
            $league_gotten = 0;
          } else {
            ($league3, $game3 ) = $ds->LookupLeague( "Viasat_LeagueDK", $bline );
            print Dumper($league3, $game3);
            print Dumper(split("-", $teams_cat));
          }
        }

        ## Finnish
        if($chd->{xmltvid} =~ /\.fi$/i) {
          # These are not real sports games
          ($league3, $game3 ) = $ds->LookupLeague( "Viasat_LeagueFI", $one );
          print Dumper($league3, $game3);
          print Dumper(split("-", $teams_cat));
        }

        ## Swedish
        if($chd->{xmltvid} =~ /\.se$/i) {
          # These are not real sports games
          ($league3, $game3 ) = $ds->LookupLeague( "Viasat_LeagueSE", $one );
          print Dumper($league3, $game3);
          print Dumper(split("-", $teams_cat));
        }

        ## Norway
        if($chd->{xmltvid} =~ /\.no$/i) {
          # These are not real sports games
          if($bline =~ /(H.ydepunkter|Magasin)/i) {
            $league_gotten = 0;
          } else {
            ($league3, $game3 ) = $ds->LookupLeague( "Viasat_LeagueNO", $bline );
            print Dumper($league3, $game3);
            print Dumper(split("-", $teams_cat));
          }
        }

        # Get game
        my ( $pty2, $game2 );
        if($league_gotten and (( $pty2, $game2 ) = $ds->LookupCat( 'Viasat_games', $game ))) {
          $extra->{sport}->{game}   = lc($game2);
        }

        # Date should be in synopsis, but if its live then its the current day's date
        if($league_gotten and ($desc_logline =~ /\((.*?)\)$/)) {
          if(my $dateparsed = ParseDate($1)) {
            $extra->{sport}->{date} = $dateparsed;
          }
        } elsif($league_gotten and defined($ce->{live}) and $ce->{live} eq "1") {
          $extra->{sport}->{date} = $currdate;
        }

        # Round
        if($league_gotten and defined($desc_logline) and ($desc_logline =~ /Omg.ng (\d+)/i)) {
          $extra->{sport}->{round} = $1;
        }elsif($league_gotten and defined($desc_logline) and ($desc_logline =~ /(\d+)\. Runde/i)) {
          $extra->{sport}->{round} = $1;
        }

      }

  	  #$ce->{external_ids} = 'viasat_' . $emission->findvalue( 'uniqueId' ); # only for non-commercial
      $ce->{extra} = $extra;

      progress( "Viasat: $chd->{xmltvid}: $start_time - $name" );
      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  $str =~ s/ ja /, /g;
  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    s|.*\s+\((.*?)\)$|$1|; # "Stīvens R. Monro (Steven R. Monroe)"
    s/^.*\s+-\s+//; # The character name is sometimes given . Remove it.
  }

  return join( ";", grep( /\S/, @persons ) );
}

## For sports
sub ParseDate {
  my ( $text ) = @_;

  my( $dayname, $day, $month, $year );

  #
  if( $text =~ /^\d+\.\d+\.\d+$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/i );
  }elsif( $text =~ /^\d+\/\d+\-\d+$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\-(\d+)$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%04d-%02d-%02d', $year, $month, $day );
}

1;

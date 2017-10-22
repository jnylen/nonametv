package NonameTV::Augmenter::Tvdb2;

use strict;
use warnings;

use TVDB2;
use utf8;
use Data::Dumper;
use Text::LevenshteinXS qw(distance);
use Encode;

use NonameTV qw/norm normUtf8 AddCategory RemoveSpecialChars CleanSubtitle/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{UserKey} )  or die "You must specify UserKey";
    defined( $self->{Language} ) or die "You must specify Language";

    $self->{tvdb2} = TVDB2->new(
        apikey => $self->{ApiKey},
        username => $self->{Username},
        userkey => $self->{UserKey},
        lang   => $self->{Language},
        debug => 1
    );

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self->{OnlyAugmentFacts} ) ){
      $self->{OnlyAugmentFacts} = 0;
    }

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    $self->{search} = $self->{tvdb2}->search();

    return $self;
}

sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode, $ceref )=@_;

  ########## SERIES INFO


  # Genres


  # YOU HAVE GUESTS in $episodes->guest_stars
  # CREW IN $EPISODES->crew

  # Actors
  my $actors = $series->actors;
  my @actors_array = ();
  if (exists($actors->{data})) {
    foreach my $actor ( @{ $actors->{data} } ){
      my $name = normUtf8( norm ( $actor->{name} ) );

      # Role played
      if( defined ($actor->{role}) and $actor->{role} ne "" ) {
        $name .= " (".normUtf8( norm ( $actor->{role} ) ).")";
      }

       push @actors_array, $name;
    }
  }

  # Genre
  my @cats;
  if( exists( $series->info()->{genre} ) ){
    foreach my $genre ( @{ $series->info()->{genre} } ){
      print Dumper($genre);
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvdb2", $genre );
      # set category, unless category is already set!
      push @cats, $categ if defined $categ;
    }
    my $cat = join "/", @cats;
    AddCategory( $resultref, undef, $cat );
  }

  ############ EPISODE
  # Fetch more episode data?
  my $newepisodedata = $self->{tvdb2}->episode( id => $episode->{id})->info;
  my $newepisode = undef;
  if(exists($newepisodedata->{data})) {
    $newepisode = $newepisodedata->{data};
  }

  # Guest stars
  # always add the episode cast
  if( defined($newepisode) and $newepisode->{guestStars} ) {
    foreach my $gactor ( @{ $newepisode->{guestStars} } ) {
      push( @actors_array, $gactor );
    }
  }
  foreach( @actors_array ){
    $_ = normUtf8( norm( $_ ) );
    if( $_ eq '' ){
      $_ = undef;
    }
  }
  @actors_array = grep{ defined } @actors_array;

  # firstAired
  if( $episode->{firstAired} ) {
    $resultref->{production_date} = $episode->{firstAired};
  }

  # Subtitle / Episode num
  if( $episode->{airedSeason} == 0 ){
    # it's a special
    $resultref->{episode} = undef;
    $resultref->{subtitle} = norm( "Special - ".$episode->{episodeName} );
  }else{
    $resultref->{episode} = sprintf( "%d . %d . ", $episode->{airedSeason}-1, $episode->{airedEpisodeNumber}-1 );

    # use episode title
    #print Dumper($episode);
    $resultref->{subtitle} = norm( $episode->{episodeName} ) if(norm( $episode->{episodeName} ) ne "" and (!defined($ceref->{subtitle}) or $ceref->{subtitle} eq ""));
  }

  # Use episode rating if there are more then MinRatingCount ratings for the episode. If the
  # episode does not have enough ratings consider using the series rating instead (if that has enough ratings)
  # if not rating qualifies leave it away.
  # the Rating at Tvdb is 1-10, turn that into 0-9 as xmltv ratings always must start at 0
  if(defined($newepisode) and exists($newepisode->{siteRatingCount}) and defined($self->{MinRatingCount})) {
  	if( $newepisode->{siteRatingCount} >= $self->{MinRatingCount} ){
    	$resultref->{'star_rating'} = $newepisode->{siteRating}-1 . ' / 9';
  	} elsif( $series->info->{siteRatingCount} >= $self->{MinRatingCount} ){
    	$resultref->{'star_rating'} = $series->info->{siteRating}-1 . ' / 9';
  	}
  }

  $resultref->{program_type} = 'series';

  # Add actors
  if( @actors_array ) {
  	  # replace programme's actors
	  $resultref->{actors} = join( ';', @actors_array );
	} else {
	  # remove existing actors from programme
	  $resultref->{actors} = undef;
  }

  # add directors
  if(defined($newepisode)) {
    $resultref->{directors} = join( ';', @{ $newepisode->{directors} } );
  }

  # add writers
  if(defined($newepisode)) {
    $resultref->{writers} = join( ';', @{ $newepisode->{writers} } );
  }

  ############ EXTERNAL LINKS

  $resultref->{url} = sprintf(
    'http://thetvdb.com/?tab=episode&id=%d&seasonid=%d&id=%d',
    $series->info->{id}, $episode->{airedSeasonID}, $episode->{id}
  );
  $resultref->{extra_id} = $series->info->{ id };
  $resultref->{extra_id_type} = "thetvdb";
}

sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};

  # result string, empty/false for success, message/true for failure
  my $result = '';
  my $matchby = undef;

  # episodeabs
  my( $episodeabs );

  # It guesses what it needs
  if( $ruleref->{matchby} eq 'guess' ) {
    # Subtitles, no episode
    if(defined($ceref->{subtitle}) && !defined($ceref->{episode})) {
    	# Match it by subtitle
    	$matchby = "episodetitle";
    } elsif(!defined($ceref->{subtitle}) && defined($ceref->{episode})) {
    	# The opposite, match it by episode
    	$matchby = "episodeseason";
    } elsif(defined($ceref->{subtitle}) && defined($ceref->{episode})) {
        # Check if it has season otherwise title.
        my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
        if( (defined $episode) and (defined $season) ){
            $matchby = "episodeseason";
        } else {
            $matchby = "episodetitle";
        }
    } else {
    	# Match it by seriesname (only change series name) here later on maybe?
    	return( undef, 'couldn\'t guess the right matchby, sorry.' );
    }
  } else {
    $matchby = $ruleref->{matchby};
  }

  return( undef, 'matchby was undefined?' ) if !defined($matchby);

#  if( $ceref->{url} && $ceref->{url} =~ m|^http://thetvdb\.com/| ) {
#    $result = "programme is already linked to thetvdb, ignoring";
#    $resultref = undef;
#} els
  if( $matchby eq 'episodeseason' ) {
    # Find episode by season and episode.

    if( defined $ceref->{episode} ){
      my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # It had episode and season!
      if( (defined $episode) and (defined $season) ){
        $episode += 1;
        $season += 1;

        my $series = $self->find_series($ceref, $ruleref);

        # Matched?
        if( (defined $series)){
          # match episode
          if(($season ne "") and ($episode ne "")) {
            #print $series->info->{name};
            my $episode2 = $series->episode({episode => $episode, season => $season});

            # Fil?
          	if( defined( $episode2 ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }

        }

      }

    }

  } elsif( $matchby eq 'episodetitle' ) {
    ## You need to fetch first the show,
    ## then the season one by one to get the titles.

    if( defined($ceref->{subtitle}) or defined($ceref->{original_subtitle}) ){

      my $series = $self->find_series($ceref, $ruleref);

      # Match shit
      if( (defined $series) ){
        # Check if the year matches
        my $epid = undef;

        # Find by episode title
        my $eps = $self->find_episode_by_name($ceref, $ruleref, $series);
        if(defined($eps)) {
          $epid = $eps->{id};
        }

        # match
        if(defined($epid)) {
          # Matched!
          my $episode2 = $series->episode({episodeid => $epid});

          # Fil?
          if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            $self->FillHash( $resultref, $series, $episode2, $ceref );
          } else {
            if(defined($ceref->{subtitle})) {
              w( "episode not found by title nor org subtitle: " . $ceref->{title} . " - \"" . $ceref->{subtitle} . "\"" );
            }

            if(defined($ceref->{original_subtitle})) {
              w( "episode not found by title nor org subtitle: " . $ceref->{title} . " - \"" . $ceref->{original_subtitle} . "\"" );
            }
          }
        } else {
          w( "episode not found by title nor org subtitle: " . $ceref->{title} );
        }

      }
    }
  } else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}

# Find series
sub find_series($$$ ) {
  my( $self, $ceref, $ruleref )=@_;

  my $series;
  my @candidates;
  my @results;
  my @ids = ();
  my @keep = ();
  my $candidate;

  # It have an series id, so you don't need to search
  if( defined( $ruleref->{remoteref} ) ) {
    return $self->{tvdb2}->series( id => $ruleref->{remoteref} );
  } else {
    @candidates = $self->{search}->series( $ceref->{title} );

    foreach my $c ( @candidates ){
      if( defined( $c->{id} ) ) {
        push( @ids, $c->{id} );
      }
    }

    print ("HELLO\n");


    # No data? Try the original title
    if(defined $ceref->{original_title} and $ceref->{original_title} ne "" and $ceref->{original_title} ne $ceref->{title}) {
      my @org_candidates = $self->{search}->series( $ceref->{original_title} );

      foreach my $c2 ( @org_candidates ){
        # It can't be added already
        if ( !(grep $_ eq $c2->{id}, @ids) ) {
          push( @candidates, $c2 );
        }
      }
    }

    # no results?
    my $numResult = @candidates;

    if( $numResult < 1 ){
      return undef;
    }

    # Check actors
    if( scalar(@candidates) >= 1 and ( $ceref->{actors} ) ){
      my @actors = split( /;/, $ceref->{actors} );
      my $match = 0;

      # loop over all remaining movies
      while( @candidates ) {
        my $candidate = shift( @candidates );

        if( defined( $candidate->{id} ) ) {
          # we have to fetch the remaining candidates to peek at the directors
          my $tvid = $candidate->{id};
          my $movie = $self->{tvdb2}->series( id => $tvid );

          my @names = ( );
          foreach my $cast ( $movie->actors ) {
            push( @names, $cast->name );
          }

          my $matches = 0;
          if( @names == 0 ){
            my $url = 'http://thetvdb.com/?tab=series&id=' . $candidate->{ id };
            w( "actors not on record, removing candidate. Add it at $url." );
          } else {
            foreach my $a ( @actors ) {
              foreach my $b ( @names ) {
                $a =~ s/(\.|\,)//;
                $b =~ s/(\.|\,)//;
                $a =~ s/ \(.*?\)//;
                $b =~ s/ \(.*?\)//;

                if( lc norm( $a ) eq lc norm( $b ) ) {
                  $matches += 1;
                }
              }
            }
          }

          if( $matches == 0 ){
            d( "actors '" . $ceref->{actors} ."' not found, removing candidate" );
          } else {
            push( @keep, $candidate );
          }
        }else{
          w( "got a tv result without id as candidate! " . Dumper( $candidate ) );
        }
      }

      @candidates = @keep;
      @keep = ();
    }

    # need to be the correct year if available
    if( scalar(@candidates) > 1 and $ceref->{production_date} and $ceref->{production_date} ne "" ) {
      my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
      while( @candidates ) {
        $candidate = shift( @candidates );

        # verify that production and release year are close
        my $released = $candidate->{ firstAired };
        $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;

        # released
        if( !$released ){
          my $url = 'http://thetvdb.com/?tab=series&id=' . $candidate->{ id };
          w( "year of release not on record, removing candidate. Add it at $url." );
        } elsif( $released >= ($produced+2) ){
          # Sometimes the produced year is actually the produced year.
          d( "first aired of the series '$released' is later than the produced '$produced'" );
        } else {
          push( @keep, $candidate );
        }

      }

      @candidates = @keep;
      @keep = ();
    }

    # Still more than x amount in array then try to get the correct show based on title or org title
    if(scalar(@candidates) > 1) {
      while( @candidates ) {
        $candidate = shift( @candidates );

        # So shit doesn't get added TWICE
        my $match2 = 0;

        # Title matched?
        if(distance( lc(RemoveSpecialChars($ceref->{title})), lc(RemoveSpecialChars($candidate->{name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }

        if(!$match2 and defined($ceref->{original_title}) and distance( lc(RemoveSpecialChars($ceref->{original_title})), lc(RemoveSpecialChars($candidate->{name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }
      }

      @candidates = @keep;
      @keep = ();
    }

    # Matches
    if( ( @candidates == 0 ) || ( @candidates > 1 ) ){
      my $warning = 'search for "' . $ceref->{title} . '"';
      if( $ceref->{production_date} ){
        $warning .= ' from ' . $ceref->{production_date} . '';
      }
      if( $ceref->{countries} ){
        $warning .= ' in "' . $ceref->{countries} . '"';
      }
      if( @candidates == 0 ) {
        $warning .= ' did not return any good hit, ignoring';
      } else {
        $warning .= ' did not return a single best hit, ignoring';
      }
      w( $warning );
    } else {
      return $self->{tvdb2}->series( id => $candidates[0]->{id} );
    }
  }

  return undef;

}

# Find episode by name
sub find_episode_by_name($$$$ ) {
  my( $self, $ceref, $ruleref, $series )=@_;

  my($season, $episode, $subtitle, $org_subtitle);

  # Subtitles
  if(defined $ceref->{subtitle}) {
    $subtitle = lc(RemoveSpecialChars(CleanSubtitle($ceref->{subtitle})));
  }
  if(defined $ceref->{original_subtitle}) {
    $org_subtitle = lc(RemoveSpecialChars(CleanSubtitle($ceref->{original_subtitle})));
  }

  # Each season check for eps
  my $hitcount = 0;
  my $hit;
  foreach my $eps ( @{ $series->episodes } ){
    next if(!defined($eps->{episodeName}) or $eps->{episodeName} eq "");
    my $epsname = lc(RemoveSpecialChars(CleanSubtitle($eps->{episodeName})));

    # Match eps name
    if( defined($subtitle) and distance( $epsname, $subtitle ) <= 2 ){
      $hitcount ++;
      $hit = $eps;
      next;
    }

    # Match eps name (org)
    if( defined($org_subtitle) and distance( $epsname, $org_subtitle ) <= 2 ){
      $hitcount ++;
      $hit = $eps;
      next;
    }
  }

  # Return season and episode if found
  if( $hitcount == 1){
    return( $hit );
  } else {
    return undef;
  }
}

1;

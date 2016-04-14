package NonameTV::Augmenter::TmdbTV;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use TMDB;

use NonameTV qw/AddCategory AddCountry norm ParseXml/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Language} ) or die "You must specify Language";

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self->{OnlyAugmentFacts} ) ){
      $self->{OnlyAugmentFacts} = 0;
    }

    # need config for main content cache path
    my $conf = ReadConfig( );

    my $cachedir = $conf->{ContentCachePath} . '/' . $self->{Type};

    $self->{themoviedb} = TMDB->new(
        apikey => $self->{ApiKey},
        lang   => $self->{Language},
        cache  => $cachedir,
    );

    $self->{search} = $self->{themoviedb}->search(
        include_adult => 'false',  # Include adult results. 'true' or 'false'
    );

    return $self;
}


sub FillCast( $$$$$ ) {
  my( $self, $resultref, $credit, $series, $episode )=@_;

  my @credits = ( );
  if(!defined($episode->{credits})) {
    foreach my $castmember ( @{ $episode->{credits}->{cast} } ){
      my $name = $castmember->{'name'};
      my $role = $castmember->{'character'};
      if( $role ) {
        # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
        if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
          $name .= ' (' . $role . ')';
        } else {
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
        }
      }
      push( @credits, $name );
    }
  }

  foreach my $guests ( @{ $episode->{guest_stars} } ){
    my $name = $guests->{'name'};
    my $role = $guests->{'character'};
    if( $role ) {
      # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
      if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
        $name .= ' (' . $role . ')';
      } else {
        w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
      }
    }
    push( @credits, $name );
  }

  if( @credits ) {
    $resultref->{$credit} = join( ';', @credits );
  }
}


sub FillCrew( $$$$$$ ) {
  my( $self, $resultref, $credit, $series, $episode, $job )=@_;

  my @credits = ( );
  foreach my $crewmember ( @{ $episode->{crew} } ){
    if( $crewmember->{'job'} eq $job ){
      my $name = $crewmember->{'name'};
      push( @credits, $name );
    }
  }
  if( @credits ) {
    $resultref->{$credit} = join( ';', @credits );
  }
}


sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode, $ceref )=@_;

  ########## SERIES INFO

  # Org title
  if( defined( $series->info->{original_name} ) and ($ceref->{title} ne $series->info->{original_name}) ){
    $resultref->{original_title} = norm( $series->info->{original_name} );
  }

  # Genres
  if( exists( $series->info->{genres} ) ){
    my @genres = @{ $series->info->{genres} };
    my @cats;
    foreach my $node ( @genres ) {
      my $genre_id = $node->{id};
      my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tmdb_genre", $genre_id );
      push @cats, $categ if defined $categ;
    }
    my $cat = join "/", @cats;
    AddCategory( $resultref, "series", $cat );
  }

  # Origin country
  if( exists( $series->info->{production_countries} ) ){
    my @countries;
    my @production_countries = @{ $series->info->{production_countries} };
    foreach my $node2 ( @production_countries ) {
      my $c_id = $node2->{iso_3166_1};
      #my ( $country ) = $self->{datastore}->LookupCountry( "Tmdb_country", $c_id );
      push @countries, $c_id if defined $c_id;
    }
    my $country2 = join "/", @countries;
    AddCountry( $resultref, $country2 );
  }

  # YOU HAVE GUESTS in $episodes->guest_stars
  # CREW IN $EPISODES->crew

  ############ EPISODE

  if( $episode->{air_date} ) {
    $resultref->{production_date} = $episode->{air_date};
  }

  # Find total number of episodes in a season
  my $total_eps = undef;
  foreach my $seasons ( @{ $series->info->{seasons} } ){
    next if ($seasons->{season_number} != $episode->{season_number});

    $total_eps = $seasons->{episode_count};
  }


  # Subtitle / Episode num
  if( $episode->{season_number} == 0 ){
    # it's a special
    $resultref->{episode} = undef;
    $resultref->{subtitle} = norm( "Special - ".$episode->{name} );
  }else{
    if(defined($total_eps)) {
      $resultref->{episode} = sprintf( "%d . %d/%d . ", $episode->{season_number}-1, $episode->{episode_number}-1, $total_eps );
    } else {
      $resultref->{episode} = sprintf( "%d . %d . ", $episode->{season_number}-1, $episode->{episode_number}-1 );
    }


    # use episode title
    $resultref->{subtitle} = norm( $episode->{name} ) if not defined $ceref->{original_subtitle};
  }

  # Ratings
  if( defined( $episode->{vote_count} ) ){
    my $votes = $episode->{vote_count};
    if( $votes >= $self->{MinRatingCount} ){
      # ratings range from 0 to 10
      $resultref->{'star_rating'} = $episode->{vote_average} . ' / 10';
    }
  }

  ############ Add actors etc

  $self->FillCast( $resultref, 'actors', $series, $episode );

  $self->FillCrew( $resultref, 'directors', $series, $episode, 'Director');
  $self->FillCrew( $resultref, 'producers', $series, $episode, 'Producer');
  $self->FillCrew( $resultref, 'writers', $series, $episode, 'Screenplay');
  $self->FillCrew( $resultref, 'writers', $series, $episode, 'Writer');


  ############ EXTERNAL LINKS

  $resultref->{url} = sprintf(
    'https://www.themoviedb.org/tv/%d/season/%d/episode/%d',
    $series->info->{id}, $episode->{season_number}, $episode->{episode_number}
  );
  $resultref->{extra_id} = $series->info->{ id };
  $resultref->{extra_id_type} = "themoviedb";
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  # It guesses what it needs
  if( $ruleref->{matchby} eq 'guess' ) {
    # Subtitles, no episode
    if(defined($ceref->{subtitle}) && !defined($ceref->{episode})) {
    	# Match it by subtitle
    	$ruleref->{matchby} = "episodetitle";
    } elsif(!defined($ceref->{subtitle}) && defined($ceref->{episode})) {
    	# The opposite, match it by episode
    	$ruleref->{matchby} = "episodeseason";
    } elsif(defined($ceref->{subtitle}) && defined($ceref->{episode})) {
        # Check if it has season otherwise title.
        my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
        if( (defined $episode) and (defined $season) ){
          # Not all seasons are aired in different years so don't make it standard until some kind of
          # solution is fixed for this.
          #if($season > 1800) {
          #  $ruleref->{matchby} = "episodeyear";
          #} else {
            $ruleref->{matchby} = "episodeseason";
          #}
        } else {
            $ruleref->{matchby} = "episodetitle";
        }
    } else {
    	# Match it by seriesname (only change series name) here later on maybe?
    	return( undef, 'couldn\'t guess the right matchby, sorry.' );
    }
  }

  # Match bys
  if( $ceref->{url} && $ceref->{url} =~ m|^http://www\.themoviedb\.org/tv/\d+$| ) {
    $result = "programme is already linked to themoviedb.org, ignoring";
    $resultref = undef;

  } elsif( $ruleref->{matchby} eq 'episodeabs' ) {
    # match by absolute episode number from program hash. USE WITH CAUTION, NOT EVERYONE AGREES ON ANY ORDER!!!

    if( defined $ceref->{episode} ){
      my( $episodeabs )=( $ceref->{episode} =~ m|^\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # Found!
      if( defined $episodeabs ){
        $episodeabs += 1;

        my $series;
        my @candidates;

        # It have an series id, so you don't need to search
        if( defined( $ruleref->{remoteref} ) ) {
          $series = $self->{themoviedb}->tv( id => $ruleref->{remoteref} );
        } else {
          @candidates = $self->{search}->tv( $ceref->{title} );
          my $resultnum = @candidates;

          # Results?
          if( $resultnum > 0 ) {
            $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
          }

          # No data? Try the original title
          if((!defined($resultnum) or $resultnum == 0) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
            @candidates = $self->{search}->tv( $ceref->{original_title} );
            $resultnum = @candidates;

            # Results?
            if( $resultnum > 0 ) {
              $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
            }
          }

        }

        # Matched?
        if( (defined $series)){
          # Calculate episode absolutes
          my $old_totaleps = 0;
          my $new_totaleps = 0;
          my $episode = undef;
          my $season = undef;

          foreach my $seasons ( @{ $series->info->{seasons} } ){
            $new_totaleps = $old_totaleps + $seasons->{episode_count};

            # Check if the episode num is in range
            if(($old_totaleps < $episodeabs) and ($new_totaleps >= $episodeabs)) {
              $season = $seasons->{season_number};
              $episode = $new_totaleps-$episodeabs;

              $old_totaleps = $new_totaleps;

              # last in foreach
              last;
            } else {
              $old_totaleps = $new_totaleps;
            }
          }

          # Nothing found
          if(!defined($episode)) {
            w( "no episode with absolute number " . $episodeabs . " found for '" . $ceref->{title} . "'" );
          } else {
            #print $series->info->{name};
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
          	if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }

        }

      }

    }

  } elsif( $ruleref->{matchby} eq 'episodeseason' ) {
    # Find episode by season and episode.

    if( defined $ceref->{episode} ){
      my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # It had episode and season!
      if( (defined $episode) and (defined $season) ){
        $episode += 1;
        $season += 1;

        my $series;
        my @candidates;

        # It have an series id, so you don't need to search
        if( defined( $ruleref->{remoteref} ) ) {
          $series = $self->{themoviedb}->tv( id => $ruleref->{remoteref} );
        } else {
          @candidates = $self->{search}->tv( $ceref->{title} );
          my $resultnum = @candidates;

          # Results?
          if( $resultnum > 0 ) {
            $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
          }

          # No data? Try the original title
          if((!defined($resultnum) or $resultnum == 0) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
            @candidates = $self->{search}->tv( $ceref->{original_title} );
            $resultnum = @candidates;

            # Results?
            if( $resultnum > 0 ) {
              $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
            }
          }

        }

        # Matched?
        if( (defined $series)){
          # match episode
          if(($season ne "") and ($episode ne "")) {
            #print $series->info->{name};
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
          	if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }

        }

      }

    }

  } elsif( $ruleref->{matchby} eq 'episodeyear' ) {
    # Find episode by season and episode.

    if( defined $ceref->{episode} ){
      my( $year, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # It had episode and season!
      if( (defined $episode) and (defined $year) ){
        $episode += 1;
        $year += 1;

        my $series;
        my @candidates;

        # It have an series id, so you don't need to search
        if( defined( $ruleref->{remoteref} ) ) {
          $series = $self->{themoviedb}->tv( id => $ruleref->{remoteref} );
        } else {
          @candidates = $self->{search}->tv( $ceref->{title} );
          my $resultnum = @candidates;

          # Results?
          if( $resultnum > 0 ) {
            $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
          }

          # No data? Try the original title
          if((!defined($resultnum) or $resultnum == 0) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
            @candidates = $self->{search}->tv( $ceref->{original_title} );
            $resultnum = @candidates;

            # Results?
            if( $resultnum > 0 ) {
              $series = $self->{themoviedb}->tv( id => $candidates[0]->{id} )
            }
          }

        }

        # Matched?
        if( (defined $series) and ($year ne "") and ($episode ne "")){
          # Check if the year matches
          my $season = undef;
          foreach my $seasons ( @{ $series->info->{seasons} } ){
            # Next if these shits fucks up
            next if($seasons->{season_number} == 0);
            next if(!defined($seasons->{air_date}) or $seasons->{air_date} == "");

            # Get air year
            my( $season_year ) = ($seasons->{air_date} =~ /^(\d\d\d\d)/);
            next if(!defined($season_year) or $year != $season_year);

            # Season!
            $season = $seasons->{season_number};
            w( "matched (year: $year) " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          }

          # Not Matched
          if(!defined($season)) {
            w( "no season found for year " . $season . " for '" . $ceref->{title} . "'" );
          } else {
            # Matched!
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
            if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
              $self->FillHash( $resultref, $series, $episode2, $ceref );
            } else {
              w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
            }

          }


        }

      }
    }
  } elsif( $ruleref->{matchby} eq 'episodetitle' ) {
    ## You need to fetch first the show,
    ## then the season one by one to get the titles.
    ##

  } elsif( $ruleref->{matchby} eq 'episodeid' ) {
    w( "TMDB doesnt provide an API CALL with episode ids." );
  } else {
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }


  return( $resultref, $result );
}


1;

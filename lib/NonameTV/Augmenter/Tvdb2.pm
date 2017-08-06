package NonameTV::Augmenter::Tvdb2;

use strict;
use warnings;

use TVDB2;
use utf8;
use Data::Dumper;

use NonameTV qw/norm normUtf8 AddCategory/;
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
        userkey => $self->{Userkey},
        lang   => $self->{Language},
    );

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self->{OnlyAugmentFacts} ) ){
      $self->{OnlyAugmentFacts} = 0;
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

  ############ EPISODE



  ############ EXTERNAL LINKS

  $resultref->{url} = sprintf(
    'http://thetvdb.com/?tab=series&id=%d',
    $series->info->{id}
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

  if( $ceref->{url} && $ceref->{url} =~ m|^http://www\.thetvdb\.com/| ) {
    $result = "programme is already linked to thetvdb, ignoring";
    $resultref = undef;
  }else{
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

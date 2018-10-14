package NonameTV::Importer::Discovery_Norway;

=pod

This importer works for both Discovery Networks Norway.
It downloads per day xml files from respective channel's
pressweb. The files are in xml-style

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
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MinDays} = 0 unless defined $self->{MinDays};
    $self->{MaxDays} = 25 unless defined $self->{MaxDays};

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Oslo" );
  	$self->{datastorehelper} = $dsh;

  	$self->{datastore}->{augment} = 1;

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  $mech->get("http://presse.discovery.no/brukere/logginn");

  $mech->submit_form(
      with_fields => {
	       'user[email]'    => $self->{Username},
	       'user[password]' => $self->{Password},
      },
      button => 'commit',
  );

  if( $mech->content =~ /notice-box/ ) {
    return undef;
  }
  else {
    return "Login failed";
  }
}

sub first_day_of_week
{
  my ($year, $week) = @_;

  # Week 1 is defined as the one containing January 4:
  DateTime
    ->new( year => $year, month => 1, day => 4, hour => 00, minute => 00, time_zone => 'Europe/Oslo' )
    ->add( weeks => ($week - 1) )
    ->truncate( to => 'week' );
} # end first_day_of_week

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $datefirst = first_day_of_week( $year, $week ); # monday

  my $url = "http://presse.discovery.no/tablaa.xml?channel=" . $chd->{grabber_info} . "&show_type=all&utf8=%E2%9C%93&week=" . $datefirst->ymd("-");

  print("Fetching $url...\n");

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)$/);


  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
  my $xmltvid = $chd->{xmltvid};

 	#$dsh->StartDate( $date , "00:00" );

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }

  # Find all "Schedule"-entries.
  my $ns_day = $doc->find( "//day" );


  if( $ns_day->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }

  my $currdate = "x";


  foreach my $dc ($ns_day->get_nodelist)
  {
    # day
    my $dayte = $dc->findvalue( '@date' );
    if( $dayte ne $currdate ){
        progress("Date is ".$dayte);

        $dsh->StartDate( $dayte , "06:00" );
        $currdate = $dayte;
    }

    # Airings
    my $ns = $dc->find( "./program" );

    foreach my $sc ($ns->get_nodelist)
    {
      my $start = $sc->findvalue( './starttime' );
      my $end   = $sc->findvalue( './endtime' );

      my ($start2, $stop2);
      try {
        $start2 = $self->create_dt( $start );
        $stop2 = $self->create_dt( $end );
      }
      catch { print("error: $_"); next; };
      next if(!defined($start2));
      next if(!defined($stop2));

      my $title_original = $sc->findvalue( './originaltitle' );
  	  my $title_programme = $sc->findvalue( './title' );
  	  my $title = norm($title_programme) || norm($title_original);

  	  $title =~ s/^Premiere: //g;
  	  $title =~ s/^Sesongpremiere: //g;

      my $durat  = $start2->delta_ms($stop2)->in_units('minutes');
      ## END

      my $hd = $sc->findvalue( './hd' );

      my $desc = undef;
      my $desc_episode = $sc->findvalue( './shortdescription' );
    	$desc = norm($desc_episode);

    	my $genre           = $sc->findvalue( './category' );
    	my $production_year = $sc->findvalue( './productionyear' );
    	my $episode         =  $sc->findvalue( './episode' );
    	my $numepisodes     =  $sc->findvalue( './numepisodes' );
    	my $subtitle        = $sc->findvalue( './episodetitle' );
      my $rerun           = $sc->findvalue( './rerun' );


    	# TVNorge seems to have the season in the originaltitle, weird.
    	# �r 2
      my ( $dummy, $dseason ) = ($title_original =~ /(.r|sesong)\s*(\d+)$/ );
      my $sseason = $sc->findvalue( './season' );
      my $season = ($sseason || $dseason);

    	progress("TVNorge: $chd->{xmltvid}: $start2 - $title");

      my $ce = {
        title 	  => norm($title),
        channel_id  => $chd->{id},
        description => norm($desc),
        start_time  => $start2->hms(':'),
      };

      # Extra
      my $extra = {};
      $extra->{descriptions} = [];
      $extra->{qualifiers} = [];
      $extra->{images} = [];


      if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      $genre =~ s/fra (\d+)//g;

      if( $genre ){
          my($country, $genretext) = ($genre =~ /^(.*?)\s+(.*?)$/);
          $country = norm($country);
          $genretext = norm($genretext);
          $genretext =~ s/\.$//g;
          $country =~ s/\.$//g;

          $genretext =~ s/\[(.*?)\]//g;

  		my($program_type, $category ) = $ds->LookupCat( 'TVNorge', $genretext );
  		AddCategory( $ce, $program_type, $category );

  		my($country2 ) = $ds->LookupCountry( 'TVNorge', $country );
          AddCountry( $ce, $country2 );
      }

      # Director
      my $director = norm($sc->findvalue( './director' ));
      if(defined($director) and $director ne "" and $xmltvid ne "eurosport.sbsdiscovery.no") {
          $ce->{directors} = parse_person_list($director);
          $ce->{program_type} = 'movie';
      }

      # Hosts
      my $host = norm($sc->findvalue( './host' ));
      if(defined($host) and $host ne "") {
          $ce->{presenters} = parse_person_list($host);
      }

      # Actors
      my @actors;
      my $acts = $sc->find( './/actors/actor' );
      foreach my $act ($acts->get_nodelist)
      {
          my $name = $act->to_literal;

          # Only push actors with an actual name
          if($name ne "") {
              push @actors, $name;
          }
      }

      if( scalar( @actors ) > 0 )
      {
          $ce->{actors} = join ";", @actors;
      }

  	# Episodes
  	if(($season) and ($episode) and ($numepisodes)) {
  		$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $numepisodes );
  	} elsif(($season) and ($episode) and (!$numepisodes)) {
  		$ce->{episode} = sprintf( "%d . %d . ", $season-1, $episode-1 );
  	} elsif((!$season) and ($episode) and ($numepisodes)) {
  		$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $numepisodes );
  	} elsif((!$season) and ($episode) and (!$numepisodes)) {
  		 $ce->{episode} = sprintf( " . %d . ", $episode-1 );
  	}

  	# HD
  	if($hd eq "true")
  	{
  	    $ce->{quality} = 'HDTV';
  	}

  	# original title
      if(defined($title_original) and $title_original =~ /, (.r|sesong) (.*)/i) {
    	    $title_original =~ s/, (.r|sesong) (.*)//i;
    	}

    	$ce->{original_title} = norm($title_original) if defined($title_original) and $ce->{title} ne norm($title_original) and norm($title_original) ne "";

      if($subtitle ne "") {
          if($subtitle =~ /(.r|sesong)\s*(\d+), (\d+)\. del/i) {
              $ce->{episode} = sprintf( "%d . %d . ", $2-1, $3-1 );
          } elsif(lc($subtitle) ne lc($title)) {
              $ce->{subtitle} = norm(ucfirst(lc($subtitle)));
          }
      }

      # If duration is higher than 100 minutes (1h 40min) then its a movie
      if($durat > 100 and $subtitle eq "" and not defined($ce->{episode}) and $xmltvid ne "eurosport.sbsdiscovery.no") {
          $ce->{program_type} = 'movie';
      }

      # Rerun
      if($rerun eq "true"){
        $ce->{new} = 0;
        push @{$extra->{qualifiers}}, "repeat";
      } else {
        $ce->{new} = 1;
        push @{$extra->{qualifiers}}, "new";
      }

      # live
      my $live = $sc->findvalue( 'islive' );
      if($live eq "1"){
        $ce->{live} = 1;
        push @{$extra->{qualifiers}}, "live";
      } else {
        $ce->{live} = 0;
      }

      $ce->{extra} = $extra;

      $dsh->AddProgramme( $ce );
    }
  }


  # Success
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

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  my( $year, $month, $day, $hour, $minute, $seconds );

  ( $year, $month, $day, $hour, $minute, $seconds ) = ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$/ );
  if(!defined $year) {
    ( $year, $month, $day, $hour, $minute ) = ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );
  }


  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Oslo',
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;

package NonameTV::Importer::AllMediaBaltics;

use strict;
use warnings;

=pod

Importer for data from AllMediaBaltics.
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
use Try::Tiny;
use URI::Escape;

use NonameTV qw/ParseXml norm AddCategory AddCountry/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Tallinn" );

    # use augment
    $self->{datastore}->{augment} = 1;

    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $cref=`cat \"$file\"`;

  my $currdate = "x";

  $cref =~ s|
  ||g;
  $cref =~ s| xmlns="http://www.mtg.se/xml/weeklisting"||;
  $cref =~ s| & | &amp; |;

  my $xml = XML::LibXML->new;
  $xml->load_ext_dtd(0);
  my $doc = $xml->parse_string($cref);
  if (not defined ($doc)) {
    f ("$file   : Failed to parse.");
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
    my( $date ) = ParseDate(norm( $sched_date->findvalue( '@date' ) ), $chd->{sched_lang});
    

    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
           $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("AllMediaBaltics: Date is: $date");
    }

	  progress("AllMediaBaltics: $xmltvid: Date is $date");
    my $lastitem = 0;

    # Programmes
    my $ns2 = $sched_date->find('program');
    if( $ns2->size() == 0 ) {
      w "No programs found";
    }
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
  	  	push @actors, norm($acts);
  	  }

	    my @countries;
      my $ns4 = $emission->find( './/country' );
      foreach my $con ($ns4->get_nodelist)
  	  {
  	    my ( $c ) = $self->{datastore}->LookupCountry( "AllMediaBaltics", $con->to_literal );
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
      $extra->{external} = {};
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
  	    ( $pty, $cat ) = $ds->LookupCat( 'AMB_genre', norm($genre) );
  	  	AddCategory( $ce, $pty, $cat );
  	  }

  	  if(defined($category) and $category and $category ne "") {
        my @categorys = split(",", $category);
        my @cats;
        my $type_new;
        foreach my $node ( @categorys ) {
          my ( $type, $categ ) = $self->{datastore}->LookupCat( "AMB_category", norm($node) );
          $type_new = $type if defined $type;
        }
        AddCategory( $ce, $type_new, $cat ) if defined $type_new;
  	  }

      $ce->{extra} = $extra;

      progress( "AllMediaBaltics: $chd->{xmltvid}: $start_time - $name" );
      $dsh->AddProgramme( $ce );
    }

    
  }

  $dsh->EndBatch( 1 );

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
  my ( $text, $lang ) = @_;

  my( $dayname, $day, $month, $year );

  #
  if( $text =~ /^\d+\.\d+\.\d+$/i ){
    if($lang eq "lv") {
      ( $year, $day, $month ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/i );
    } elsif($lang eq "lt") {
      ( $year, $month, $day ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/i );
    } else {
      ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/i );
    }
    
  }elsif( $text =~ /^\d+\/\d+\-\d+$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\-(\d+)$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%04d-%02d-%02d', $year, $month, $day );
}

1;

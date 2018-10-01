package NonameTV::Importer::NRK;

use strict;
use utf8;
use warnings;

=pod

Importer for NRK.
The file downloaded is in JSON format.

=cut

use DateTime;
use JSON -support_by_pp;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;
    $self->{NO_DUPLICATE_SKIP} = 1;

    $self->{datastore}->{augment} = 1;

    return $self;
}


sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = sprintf("https://psapi.nrk.no/epg/%s?date=%s", $chd->{grabber_info}, $date);
  print ("url: $url\n");

  return( $url, undef );
}

sub ContentExtension {
  return 'json';
}

sub FilteredExtension {
  return 'json';
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

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;
  

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

  my( $date ) = ($batch_id =~ /_(.*)$/);

  $dsh->StartDate( $date, "00:00" );

  # For each 4 weeks and days
  foreach my $p (@{$data->[0]->{"entries"}}) {
        my( $episode, $ep, $eps, $seas, $dummy );
        my $title  = $p->{"title"};
        my $desc   = $p->{"description"};
        my $start  = $self->create_dt($p->{"plannedStart"})->hms(":");
        #my $end    = $p->{"end"};
        my $rerun  = $p->{"reRun"};

        # Defined?
        if(defined($desc)) {
            # Avsnitt 2:6
            ( $ep, $eps ) = ($desc =~ /\((\d+)\:(\d+)\)/ );
            $desc =~ s/\((\d+)\:(\d+)\)//;
            $desc = norm($desc);

            # Avsnitt 2
            ( $ep ) = ($desc =~ /\s+\((\d+)\)/ ) if not $ep;
            $desc =~ s/\((\d+)\)$//;
            $desc = norm($desc);

            # S�song 2
            ( $seas ) = ($desc =~ /Sesong\s*(\d+)/ );
            $desc =~ s/Sesong (\d+)(\.|)$//;
            $desc = norm($desc);

            # Age restrict
            $desc =~ s/\((\d+)(\s+|).r\)//;
            $desc = norm($desc);
        }


        # Episode info in xmltv-format
        if( (defined $ep) and (defined $seas) and (defined $eps) )
        {
          $episode = sprintf( "%d . %d/%d .", $seas-1, $ep-1, $eps );
        }
        elsif( (defined $ep) and (defined $seas) and !(defined $eps) )
        {
          $episode = sprintf( "%d . %d .", $seas-1, $ep-1 );
        }
        elsif( (defined $ep) and (defined $eps) and !(defined $seas) )
        {
          $episode = sprintf( ". %d/%s .", $ep-1, $eps );
        }
        elsif( (defined $ep) and !(defined $seas) and !(defined $eps) )
        {
          $episode = sprintf( ". %d .", $ep-1 );
        }

        # Put everything in a array
        my $ce = {
            channel_id  => $chd->{id},
            start_time  => $start,
            title       => norm($title),
            description => norm($desc),
        };

        $ce->{episode} = $episode if $episode;

        # extra
        my $extra = {};
        $extra->{titles} = [];
        $extra->{descriptions} = [];
        $extra->{qualifiers} = [];

        # Directors
        if( my( $directors ) = ($ce->{description} =~ /Regi\:\s*(.*)$/) )
    	{
      		$ce->{directors}   = parse_person_list( $directors );
      		$ce->{description} =~ s/Regi\:(.*)$//;
      		$ce->{description} = norm($ce->{description});
    	}

        # Get actors
        if( my( $actors ) = ($ce->{description} =~ /Med\:\s*(.*)$/ ) )
    	{
      		$ce->{actors}      = parse_person_list( $actors );
      		$ce->{description} =~ s/Med\:(.*)$//;
      		$ce->{description} = norm($ce->{description});
   		}

        if($ce->{title} =~ /^(Nattkino|Film|Filmsommer)\:/i) {
    	    $ce->{program_type} = "movie";

    	}

    	# Title cleanup
    	$ce->{title} =~ s/Nattkino://g;
    	$ce->{title} =~ s/Film://g;
    	$ce->{title} =~ s/Filmsommer://g;
    	$ce->{title} =~ s/Dokusommer://g;
    	$ce->{title} = norm($ce->{title});

    	# Fix title
    	if($ce->{title} =~ /, The$/i) {
    	    $ce->{title} = "The " . $ce->{title};
    	    $ce->{title} =~ s/, The$//i;
    	}

      # Defined?
        if(defined($desc)) {
            if( ($desc =~ /fr. (\d\d\d\d)\b/i) or
            ($desc =~ /fra (\d\d\d\d)\.*$/i) )
            {
                $ce->{production_date} = "$1-01-01";
            }

            my ( $subtitles ) = ($desc =~ /\((.*?)\)$/ );
            ( $subtitles ) = ($desc =~ /^\((.*?)\)/ ) if !$subtitles;
            if($subtitles) {
                my ( $realtitle, $realsubtitle ) = ($subtitles =~ /(.*)\:(.*)/ );
                if(defined($realtitle)) {
                    #$title = $realtitle;
                    $subtitles = $realsubtitle;

                    # Remove shit
                    if(defined($realtitle)) {
                        $realtitle =~ s/^"//;
                        $realtitle =~ s/"$//;
                    }

                    #$ce->{original_title} = norm($realtitle) if norm($realtitle) ne $ce->{title};
                    #$ce->{original_subtitle} = norm($realsubtitle) if !defined($ce->{program_type}) or (defined($ce->{program_type}) and $ce->{program_type} ne "movie");
                } else {
                #    $ce->{original_title} = norm($subtitles) if norm($subtitles) ne $ce->{title};
                }

            }
      }

      # Rerun
      if($rerun){
        $ce->{new} = 0;
        push @{$extra->{qualifiers}}, "repeat";
      } else {
        $ce->{new} = 1;
        push @{$extra->{qualifiers}}, "new";
      }

      $ce->{extra} = $extra;

      progress("$start : $ce->{title}");

      $dsh->AddProgramme( $ce );
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  $str =~ s/\s*med\s+fler\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\bog\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
    s/\.//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

sub create_dt ( $ )
{
  my $self = shift;
  my ($timestamp) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($unix, $tz) = ($timestamp =~ m/Date\((\d+?)00(\+\d\d\d\d)/);
    my ($month, $day, $year, $hour, $minutes) = (localtime(($unix / 10)))[4,3,5,2,1];
    $year += 1900;
    $month += 1;


    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minutes,
      time_zone => $tz
    );
    #$dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;

package NonameTV::Importer::NRK_temp;

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

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

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

  my $datefirst = first_day_of_week( $year, $week )->add( days => 0 )->epoch; # monday

  my $url = "http://snutt.nrk.no/nrkno_apps/epg/dist/backend/epg/?channel=".$chd->{grabber_info}."&time=".$datefirst;

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
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Data
  my $json = new JSON->allow_nonref;
  my $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

  my ($date, $p, $start_of_week);

  # For each 4 weeks and days
  foreach my $d (@{$data->{"days"}}) {
    # Week
    my ($date) = ($d->{"datetime"} =~ /^(\d\d\d\d-\d\d-\d\d)/);

    # Otherwise it will whine
    if( $date ne $currdate ){
        progress("Date is ".$date);

        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
    }

    # programmes
    foreach my $p (@{$d->{"entries"}}) {
        my( $episode, $ep, $eps, $seas, $dummy );
        my $title  = $p->{"title"};
        my $desc   = $p->{"description"};
        my $start  = $p->{"start"};
        my $end    = $p->{"end"};
        my $rerun  = $p->{"reRun"};
        $start =~ s/\./:/g;

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

                    $ce->{original_title} = norm($realtitle) if norm($realtitle) ne $ce->{title};
                    $ce->{original_subtitle} = norm($realsubtitle) if !defined($ce->{program_type}) or (defined($ce->{program_type}) and $ce->{program_type} ne "movie");
                } else {
                #    $ce->{original_title} = norm($subtitles) if norm($subtitles) ne $ce->{title};
                }

            }
        }

        progress("$start - $end : $ce->{title}");

        $dsh->AddProgramme( $ce );
    }
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

1;

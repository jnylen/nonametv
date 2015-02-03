package NonameTV::Importer::SkyDE;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail/ftp in gzip-files.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use PerlIO::gzip;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  # Silence
  $self->{SILENCE_DUPLICATE_SKIP} = 1;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $filename, $chd ) = @_;
  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $service_id, $usedesc ) = split( /:/, $chd->{grabber_info} );

  my $cref;
  if($filename =~ /\.gz$/i) {
      open FOO, "<:gzip", $filename or die $!;

      while (<FOO>) {
        $cref .= $_;
      }

      close (FOO);
  } else {
    $cref=`cat \"$filename\"`;
  }


  $cref =~ s|
  ||g;

  $cref =~ s| xmlns:MPExport='http://pgv.premiere.de/2004/XMLSchemaLIB/MedienportalExport'||;
  $cref =~ s| xmlns:xsi='http://www.w3.org/2001/XMLSchema'||;
  $cref =~ s| xmlns:schemaLocation='[^']+'||;

  $cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;


  my $doc;
  my $currdate = "x";
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if (not defined ($doc)) {
    f ("$filename: Failed to parse.");
    return 0;
  }

  # XPC
  my $xpc = XML::LibXML::XPathContext->new( );
  my $ns = $xpc->findnodes( '//programmElement[@service="'.$service_id.'"]', $doc );
  if( $ns->size() == 0 ) {
    f ("$filename: No data found");
    return 0;
  }

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week, $year) = ($filename =~ /presse_(\d+)_(\d\d\d\d)/);
  my $batchid = $chd->{xmltvid} . "_" . $year . "-" . $week;
  $ds->StartBatch( $batchid , $chd->{id} );

  # Sort by start
  sub by_start {
    return $xpc->findvalue('@planungsDatum', $a) cmp $xpc->findvalue('@planungsDatum', $b);
  }

  foreach my $p (sort by_start $ns->get_nodelist) {
    $xpc->setContextNode( $p );

    my $service_ch = $xpc->findvalue( '@service' );
    if($service_ch ne $service_id) { next; }

    my $title      = norm($xpc->findvalue( '@eventTitel' ));
    my $title_org  = norm($xpc->findvalue( '@origTitel' ));
    my $start      = $self->parseTimestamp($xpc->findvalue( '@planungsDatum' ));
    my $start_time = $xpc->findvalue( '@eventAnfang' );
    my $end        = $xpc->findvalue( '@eventEnde' );
    my $subtitle   = norm($xpc->findvalue( '@episodenTitel' ));
    my $subtitle_o = norm($xpc->findvalue( '@origEpisodenTitel' ));
    my $prod_year  = $xpc->findvalue( '@herstJahr' );
    my $prod_count = $xpc->findvalue( '@herstLand' );
    my $audio_form = $xpc->findvalue( '@audioFormat' );
    my $video_form = $xpc->findvalue( '@videoFormat' );
    my $genre      = $xpc->findvalue( '@zeitschriftenGenre' );
    my $movie      = $xpc->findvalue( '@spielfilmKz' );
    my $is_hd      = $xpc->findvalue( '@istHD' );
    my $is_live    = $xpc->findvalue( '@istLive' );
    my $episode_nr = $xpc->findvalue( '@EpsiodenNr' );
    my $season_nr  = $xpc->findvalue( '@Staffel' );
    my $descr      = $xpc->findvalue( '@kurzInhalt' );

    my $date = $start->ymd("-");
    if($date ne $currdate ) {
      #$dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("SkyDE: Date is: $date");
    }


    my $ce =
    {
      channel_id  => $chd->{id},
      title       => norm($title),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
    };

    $ce->{subtitle} = norm($subtitle) if $subtitle;
    $ce->{original_title} = norm($title_org) if $title_org and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
    $ce->{original_subtitle} = norm($subtitle_o) if $subtitle_o and $ce->{subtitle} ne norm($subtitle_o) and norm($subtitle_o) ne "";

    # Prod. Year
    if( $prod_year =~ m|^\d{4}$| ){
        $ce->{production_date} = $prod_year . '-01-01';
    }

    # Genre
    if( $genre ){
        my ( $program_type, $category ) = $self->{datastore}->LookupCat( "SkyDE", $genre );
        AddCategory( $ce, $program_type, $category );
    }

    # Movie
    if($movie and $movie eq "J") {
        $ce->{program_type} = 'movie';
    }

    if( (defined($season_nr) and $season_nr ne "") and (defined($episode_nr) and $episode_nr ne "") ){
        $ce->{episode} = ($season_nr - 1) . ' . ' . ($episode_nr - 1) . ' .';
        $ce->{program_type} = 'series';
    } elsif( defined($episode_nr) and $episode_nr ne "" ){
        $ce->{episode} = '. ' . ($episode_nr - 1) . ' .';
        $ce->{program_type} = 'series';
    }

    # Audio Format
    if( $audio_form ) {
      if ($audio_form eq 'Dolby Surround') {
        $ce->{stereo} = 'surround';
      } elsif ($audio_form eq 'Stereo') {
        $ce->{stereo} = 'stereo';
      }
    }

    # Video Format
    if( $video_form ){
      if ($video_form eq '16:9') {
        $ce->{aspect} = '16:9';
      } elsif ($video_form eq 'Stereo') {
        $ce->{aspect} = 'stereo';
      } elsif ($video_form eq '4:3') {
        $ce->{aspect} = '4:3';
      }
    }

    # HD
    if($is_hd eq "J") {
        $ce->{quality} = 'HDTV';
    }

    # Credits
    my (@actors, @directors, @producers);
    my $credits = $xpc->find( './/personen/person' );
    foreach my $act ($credits->get_nodelist)
    {
        my $role = $act->findvalue( '@rolle' );
        my $person = $act->findvalue( '@vorname' )." ".$act->findvalue( '@nachname' );
        my $type = $act->findvalue( '@funktion' );

        # Role
        if($person ne "" and $role ne "") {
      	    $person .= " (".$role.")";
      	}

      	# Actor
      	if ( $type eq "DA" ) {
      	    push @actors, $person;
      	} elsif( $type eq "RE" ) {
      	    push @directors, $person;
      	} elsif( $type eq "PR" ) {
      	    push @producers, $person;
      	}
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ";", @actors;
    }

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ";", @directors;
    }

    if( scalar( @producers ) > 0 )
    {
      $ce->{producers} = join ";", @producers;
    }

    # Some channels are VG:d and some are not
    if(defined($usedesc) and $usedesc eq "1") {
        $ce->{description} = norm($descr);
    }

    $ds->AddProgrammeRaw( $ce );
    progress("SkyDE: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});
  }

  $ds->EndBatch( 1 );

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => 'Europe/Berlin'
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

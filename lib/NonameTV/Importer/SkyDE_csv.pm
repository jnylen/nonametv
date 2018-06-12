package NonameTV::Importer::SkyDE_csv;

use strict;
use warnings;

=pod

Import data from CSV-files delivered. Each week is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Data::Dumper;
use IO::Scalar;
use Spreadsheet::Read;
use Date::Parse; 

use NonameTV qw/norm formattedCell AddCategory MonthNumber FixSubtitle/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

	# use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.csv$/i ){
    $self->ImportCSV( $file, $chd );
  } else {
    error( "SkyDE_CSV: Unknown file format: $file" );
  }

  return;
}

sub ImportCSV
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Process
  progress( "SkyDE_CSV: $xmltvid: Processing $file" );

  my $doc;
  eval {
    $doc = Spreadsheet::Read->new ($file, dtfmt => "yyyy-mm-dd", strip => 1, sep => "\t", quote => "@@@@@@@@@@@");
  };
  if( $@ )   {
    error( "SkyDE_CSV: $file: Failed to parse: $@" );
    return;
  }

  my $currdate = "x";

  my ($year, $week) = ($file =~ /_(\d\d\d\d)-(\d+)/);
  my $batchid = $chd->{xmltvid} . "_" . $year . "-" . $week;
  $ds->StartBatch( $batchid , $chd->{id} );

  my @ces;

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "SkyDE_CSV: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;
    my $batch_id;
    my %columns = ();

    # Rows
    #print Dumper($oWkS);
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'} = $iC    if( $oWkS->cell($iC, $iR) =~ /eventTitel/ );
            $columns{'Start'} = $iC    if( $oWkS->cell($iC, $iR) =~ /planungsDatum/ );
            $columns{'EndTime'} = $iC    if( $oWkS->cell($iC, $iR) =~ /eventEnde/ );
            $columns{'Channel'} = $iC    if( $oWkS->cell($iC, $iR) =~ /^service/ );
            $columns{'OrgTitle'} = $iC    if( $oWkS->cell($iC, $iR) =~ /origTitel/ );

            $columns{'EpTitle'} = $iC    if( $oWkS->cell($iC, $iR) =~ /^episodenTitel/ );
            $columns{'OrgEpTitle'} = $iC    if( $oWkS->cell($iC, $iR) =~ /origEpisodenTitel/ );
            $columns{'Production Year'} = $iC    if( $oWkS->cell($iC, $iR) =~ /herstJahr/ );
            $columns{'Production Country'} = $iC    if( $oWkS->cell($iC, $iR) =~ /herstLand/ );

            $columns{'Audio Format'} = $iC    if( $oWkS->cell($iC, $iR) =~ /audioFormat/ );
            $columns{'Video Format'} = $iC    if( $oWkS->cell($iC, $iR) =~ /videoFormat/ );
            $columns{'Genre'} = $iC    if( $oWkS->cell($iC, $iR) =~ /zeitschriftenGenre/ );
            $columns{'isMovie'} = $iC    if( $oWkS->cell($iC, $iR) =~ /spielfilmKz/ );
            $columns{'isHD'} = $iC    if( $oWkS->cell($iC, $iR) =~ /istHD/ );
            $columns{'isLive'} = $iC    if( $oWkS->cell($iC, $iR) =~ /istLive/ );
            $columns{'Episode Number'} = $iC    if( $oWkS->cell($iC, $iR) =~ /EpsiodenNr/ );
            $columns{'Season Number'} = $iC    if( $oWkS->cell($iC, $iR) =~ /Staffel/ );
            $columns{'Synopsis'} = $iC    if( $oWkS->cell($iC, $iR) =~ /kurzInhalt/ );
            $columns{'FSK'} = $iC    if( $oWkS->cell($iC, $iR) =~ /fsk/ );
            $columns{'Credits'} = $iC    if( $oWkS->cell($iC, $iR) =~ /personen/ );


            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /eventTitel/ ); # Only import if season number is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # Service
      my $service = norm(formattedCell($oWkS, $columns{'Channel'}, $iR));
      my $grabberinfo = $chd->{grabber_info};
      next if(norm($service) !~ /^$grabberinfo$/i);

      # Start
      next if( ! $columns{'Start'} );
      my $start = $self->parseTimestamp(formattedCell($oWkS, $columns{'Start'}, $iR));

      if( !defined( $start ) ) {
          next;
      }

      # Title
      next if( ! $columns{'Title'} );
      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));

      my $ce =
      {
        channel_id  => $chd->{id},
        title       => norm($title),
        start_time  => $start->ymd("-") . " " . $start->hms(":"),
      };

      my $subtitle = formattedCell($oWkS, $columns{'EpTitle'}, $iR);
      $ce->{subtitle} = norm($subtitle) if $subtitle;
      my $title_org = formattedCell($oWkS, $columns{'OrgTitle'}, $iR);
      $ce->{original_title} = norm($title_org) if $title_org and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      my $subtitle_o = formattedCell($oWkS, $columns{'OrgEpTitle'}, $iR);
      $ce->{original_subtitle} = norm($subtitle_o) if $subtitle_o and $ce->{subtitle} ne norm($subtitle_o) and norm($subtitle_o) ne "";

      # Prod. Year
      if( defined(formattedCell($oWkS, $columns{'Production Year'}, $iR)) and formattedCell($oWkS, $columns{'Production Year'}, $iR) =~ /^(\d{4})$/ ){
        $ce->{production_date} = $1 . '-01-01';
      }

      # Genre
      my $genre = formattedCell($oWkS, $columns{'Genre'}, $iR);
      if( $genre ){
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "SkyDE", $genre );
          AddCategory( $ce, $program_type, $category );
      }

      # Movie
      if(defined(formattedCell($oWkS, $columns{'isMovie'}, $iR)) and formattedCell($oWkS, $columns{'isMovie'}, $iR) eq "J") {
        $ce->{program_type} = 'movie';
      }

      my $episode_nr = formattedCell($oWkS, $columns{'Episode Number'}, $iR);
      my $season_nr = formattedCell($oWkS, $columns{'Season Number'}, $iR);
      if( (defined($season_nr) and $season_nr ne "" and $season_nr ne "0") and (defined($episode_nr) and $episode_nr ne "" and $episode_nr ne "0") ){
        $ce->{episode} = ($season_nr - 1) . ' . ' . ($episode_nr - 1) . ' .' if($episode_nr > 0 and $season_nr > 0);
        $ce->{program_type} = 'series';
      } elsif( defined($episode_nr) and $episode_nr ne "" and $episode_nr ne "0" ){
        $ce->{episode} = '. ' . ($episode_nr - 1) . ' .' if($episode_nr > 0);
        $ce->{program_type} = 'series';
      }

      # Audio Format
      my $audio_form = formattedCell($oWkS, $columns{'Audio Format'}, $iR);
      if( $audio_form ) {
        if ($audio_form eq 'Dolby Surround') {
            $ce->{stereo} = 'surround';
        } elsif ($audio_form eq 'Dolby Digital 5.1') {
            $ce->{stereo} = 'dolby digital';
        } elsif ($audio_form eq 'Stereo') {
            $ce->{stereo} = 'stereo';
        }
      }

      # Video Format
      my $video_form = formattedCell($oWkS, $columns{'Video Format'}, $iR);
      if( $video_form ){
        if ($video_form eq '16:9') {
            $ce->{aspect} = '16:9';
        } elsif ($video_form eq '3D 16:9') {
            $ce->{aspect} = '16:9';
        } elsif ($video_form eq '4:3') {
            $ce->{aspect} = '4:3';
        }
      }

      # HD
      my $is_hd = formattedCell($oWkS, $columns{'isHD'}, $iR);
      if($is_hd eq "J") {
        $ce->{quality} = 'HDTV';
      }

      # FSK
      my $fsk = formattedCell($oWkS, $columns{'FSK'}, $iR);
      if($fsk eq "o.A.") {
        $ce->{rating} = "FSK 0";
      }if($fsk eq "12") {
        $ce->{rating} = "FSK 12";
      } elsif($fsk eq "16") {
        $ce->{rating} = "FSK 16";
      } elsif($fsk eq "18") {
        $ce->{rating} = "FSK 18";
      } elsif($fsk eq "6") {
        $ce->{rating} = "FSK 6";
      }

      my $descr = formattedCell($oWkS, $columns{'Synopsis'}, $iR);
      $ce->{description} = norm($descr);
      $ce->{description} =~ s/^(\d+)\. Staffel, Folge (\d+)\: //i; # Remove episode info from the description

      # Actors, directors etc
      my $credits = formattedCell($oWkS, $columns{'Credits'}, $iR);
      $self->extract_credits( $ce, $credits );

      push( @ces , $ce );
    }
  }

  FlushDayData( $chd->{xmltvid}, $ds , @ces );

  $ds->EndBatch( 1 );
  return;
}

sub extract_credits
{
  my $self = shift;
  my( $ce, $credits ) = @_;

  $credits =~ s/\}\{/::/g;
  $credits =~ s/\{//g;
  $credits =~ s/\}//g;

  my @creds = split("::", $credits);
  my (@actors, @directors, @producers);

  foreach my $cred (@creds) {
    my($role, $lastname, $firstname, $dummy1, $dummy2, $dummy3, $type) = split(";", $cred);
    next if(!defined($type));
    my $person = "$firstname $lastname";

    # Role
    if($person ne "" and $role ne "") {
      $person .= " (".$role.")";
    }

    # Actor
    if ( $type eq "DA" ) {
      push @actors, norm($person);
    } elsif( $type eq "RE" ) {
      push @directors, norm($person);
    } elsif( $type eq "PR" ) {
      push @producers, norm($person);
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
}

sub FlushDayData {
  my ( $xmltvid, $ds , @data ) = @_;

    # Sort by start
    sub by_start {
        return str2time($a->{start_time}) cmp str2time($b->{start_time});
    }

    if( @data ){
      foreach my $element (sort by_start @data) {

        progress("SkyDE_CSV: $xmltvid: $element->{start_time} - $element->{title}");
        $ds->AddProgramme( $element );
      }
    }
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
    my $dt;
    eval {
        $dt = DateTime->new (
          year      => $year,
          month     => $month,
          day       => $day,
          hour      => $hour,
          minute    => $minute,
          second    => $second,
          time_zone => 'Europe/Berlin'
        );
    };

    if ($@){
      w ("Could not convert time! Check for daylight saving time border. " . $year . "-" . $month . "-" . $day . " " . $hour . ":" . $minute);
      return undef;
    }

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

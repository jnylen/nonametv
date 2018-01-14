package NonameTV::Importer::EBS_DOC;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

Episode numbers parsed from title.
Subtitles.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm MonthNumber Docxfile2Xml ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;
use Data::Dumper;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

# The lowest log-level to store in the batch entry.
# DEBUG = 1
# INFO = 2
# PROGRESS = 3
# ERROR = 4
# FATAL = 5
my $BATCH_LOG_LEVEL = 4;

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  # Depending on the file end its different import ways
  if( $file =~ /.doc$/i ) {
    $self->ImportDOC( $file, $chd );
  } elsif( $file =~ /.docx$/i ) {
    $self->ImportDOCX( $file, $chd );
  } else {
    error("unknown file: $file");
  }

}

sub ImportDOCX
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $content = Docxfile2Xml($file);

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($content); };

  if( not defined( $doc ) ) {
    error( "EBS_DOC: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( "//w:p" );

  if( $rows->size() == 0 ) {
    error( "EBS_DOC: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  foreach my $row ($rows->get_nodelist) {
    # Date Check
    if(norm($row->findvalue( 'w:r[1]/w:t' )) =~ /^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)/i) {
      my $day = $row->findvalue( 'w:r[2]/w:t' );
      my $month = $row->findvalue( 'w:r[4]/w:t' );
      my $year = $row->findvalue( 'w:r[5]/w:t' );
      print ("test: $day - $month - $year\n");
    }

    # Programme Check
  }

  #$dsh->EndBatch( 1 );
  return 1;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $chd ) = @_;

#return if( $chd->{xmltvid} !~ /privatespice\.tv\.gonix\.net/ );

  defined( $chd->{sched_lang} ) or die "You must specify the language used for this channel (sched_lang)";
  if( $chd->{sched_lang} !~ /^en$/ and $chd->{sched_lang} !~ /^se$/ and $chd->{sched_lang} !~ /^hr$/ and $chd->{sched_lang} !~ /^da$/ and $chd->{sched_lang} !~ /^sv$/ and $chd->{sched_lang} !~ /^no$/ and $chd->{sched_lang} !~ /fi$/  ){
    error( "EBS_DOC: $chd->{xmltvid} Unsupported language '$chd->{sched_lang}'" );
    return;
  }

  my $schedlang = $chd->{sched_lang};
  progress( "EBS_DOC: $chd->{xmltvid}: Setting schedules language to '$schedlang'" );

  #return if( $file !~ /\.doc$/i );

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = File2Xml( $file );
#print "DOC\n---------------\n" . $doc->toString(1) . "\n";
#return;


  if( not defined( $doc ) )
  {
    error( "EBS_DOC: $chd->{xmltvid} Failed to parse $file" );
    return;
  }

  $self->ImportFull( $file, $doc, $channel_xmltvid, $channel_id, $schedlang, $chd );
}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportFull
{
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id, $lang, $chd ) = @_;

  my $dsh = undef;

  if($chd->{grabber_info} eq "EET") {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Helsinki" );
  } else {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Amsterdam" );
  }

  # Find all div-entries.
  my $ns = $doc->find( "//div" );

  if( $ns->size() == 0 )
  {
    error( "EBS_DOC: $channel_xmltvid: No programme entries found in $filename" );
    return;
  }

  progress( "EBS_DOC: $channel_xmltvid: Processing $filename" );

  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FHEAD  => 2,   # Found head with starttime and title
    ST_FDESC  => 3,   # Found description
    ST_EPILOG => 4,   # After END-marker
  };

  use constant {
    T_HEAD => 10,
    T_DATE => 11,
    T_TEXT => 12,
    T_STOP => 13,
  };

  my $state=ST_START;
  my $currdate;

  my $start;
  my $title;
  my $date;

  my $ce = {};

  foreach my $div ($ns->get_nodelist)
  {

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

    my $type;

#print "$text\n";

    if( isDate( $text, $lang ) ){

      $type = T_DATE;
      $date = ParseDate( $text, $lang, $filename );
      if( not defined $date ) {
	       error( "EBS_DOC: $channel_xmltvid: $filename Invalid date $text" );
      }
      progress("EBS_DOC: $channel_xmltvid: Date is: $date");

    } elsif( isShow( $text ) ){

      $type = T_HEAD;
      $start=undef;
      $title=undef;

      if($text =~ /^(\d+\:\d+)\s+(.*)\s*$/) {
        ( $start, $title ) = ($text =~ /^(\d+\:\d+)\s+(.*)\s*$/ );
      } elsif($text =~ /^(\d+\.\d+)\s+(.*)\s*$/) {
        ( $start, $title ) = ($text =~ /^(\d+\.\d+)\s+(.*)\s*$/ );
      }

      $start =~ tr/\./:/;
      $title =~ s/\s+\(18\+\)//g if $title;

    } elsif( $text =~ /^\s*Programme Schedule - \s*$/ ){

      $type = T_STOP;

    } else {

      $type = T_TEXT;

    }

    if( $state == ST_START ){

      if( $type == T_TEXT ) {

        # Ignore any text before we find T_DATE

      } elsif( $type == T_DATE ) {
      	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
      	$dsh->StartDate( $date );
        $self->AddDate( $date );
      	$state = ST_FDATE;
      	next;
      } else {
	       error( "EBS_DOC: $channel_xmltvid: State ST_START, found: $text" );
      }

    } elsif( $state == ST_FHEAD ){

      if( $type == T_TEXT ){

      	if( defined( $ce->{description} ) ){

      	  $ce->{description} .= " " . $text;

      	} else {
          my($realtitle, $realsubtitle);
          # Real name is in the style of ^(name: subtitle)$
          if(($realtitle, $realsubtitle) = ($text =~ /^\((.*?)\: (.*)\)$/)) {
            $ce->{original_title} = norm($realtitle);
            $ce->{original_title} =~ s/\(Season (\d+) Specials\)//i;

            $realsubtitle =~ s|\s+-\s+part\s+(\d+)$| ($1)|i;

            $ce->{original_subtitle} = norm($realsubtitle);
          } elsif(($realtitle) = ($text =~ /^\((.*)\)$/)) {
            $ce->{original_title} = norm($realtitle);
            $ce->{original_title} =~ s/\(Season (\d+) Specials\)//i;
          } else {
            $ce->{description} = $text;
          }

      	}
      	next;

      } else {

	      extract_extra_info( $ce ) if $channel_xmltvid ne "adultchannel.co.uk";

        progress("EBS_DOC: $channel_xmltvid: $start - $ce->{title}");

        $ce->{quality} = 'HDTV' if( $channel_xmltvid =~ /hd\./ or $channel_xmltvid =~ /hdshowcase\./ );
        $ce->{title} =~ s/\(Season (\d+) Specials\)//i;

      	$dsh->AddProgramme( $ce );
      	$ce = {};
      	$state = ST_FDATE;

      }
    }

    if( $state == ST_FDATE ){

      if( $type == T_HEAD ){

      	$ce->{start_time} = $start;
      	$ce->{title} = norm($title);

      	$state = ST_FHEAD;
      } elsif( $type == T_DATE ){

      	$dsh->EndBatch( 1 );
      	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
      	$dsh->StartDate( $date );
        $self->AddDate( $date );
      	$state = ST_FDATE;

      } elsif( $type == T_STOP ){
      	$state = ST_EPILOG;
      } else {
	      error( "EBS_DOC: $channel_xmltvid: $filename State ST_FDATE, found: $text" );
      }

    } elsif( $state == ST_EPILOG ){

      if( ($type != T_TEXT) and ($type != T_DATE) ) {

        error( "EBS_DOC: $channel_xmltvid: $filename State ST_EPILOG, found: $text" );

      }
    }
  }

  $dsh->EndBatch( 1 );
}

sub extract_extra_info
{
  my( $ce ) = shift;
  my( $title, $episode, $subtitle, $season, $seasontext, $episodetext );

  # Episode information
  if( $ce->{title} ){
    if( ($title, $seasontext, $season, $subtitle, $episodetext, $episode) = ($ce->{title} =~ /(.*) \((Kausi|Season|S.song) (\d+)\)\: (.*) \((Jakso|Episode|Avsnitt|Episod) (\d+)\)$/) ) {
      $ce->{title} = norm($title);
      $ce->{subtitle} = norm($subtitle) if !($subtitle =~ /^(Episode|Episod) (\d+)/i);
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif( ($title, $seasontext, $season, $episodetext, $episode) = ($ce->{title} =~ /(.*) \((Kausi|Season|S.song) (\d+)\) \((Jakso|Episode|Avsnitt|Episod) (\d+)\)$/) ) {
      $ce->{title} = norm($title);
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif( ($title, $seasontext, $season, $episodetext, $episode) = ($ce->{title} =~ /(.*) \((Kausi|Season|S.song) (\d+), (Jakso|Episode|Avsnitt|Episod) (\d+)\)$/) ) {
      $ce->{title} = norm($title);
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif(( $title, $subtitle ) = ($ce->{title} =~ /(.*)\: (.*)/)) {
      $ce->{title} = norm($title);
      $ce->{subtitle} = norm($subtitle) if !($subtitle =~ /^(Episode|Episod) (\d+)/i);
      $ce->{program_type} = "series";

      if( ($episodetext, $episode) = ($ce->{title} =~ /^(Episode|Episod) (\d+)/) ) {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }
    }
  }

  # Subtitle?
  if($ce->{subtitle}) {
    $ce->{subtitle} =~ s|,\s+del\s+(\d+)$| ($1)|i;
    $ce->{subtitle} =~ s|\:\s+part\s+(\d+)$| ($1)|i;
    $ce->{subtitle} =~ s|\s+-\s+(\d+)\.\s+osa$| ($1)|i;
    $ce->{subtitle} =~ s|\s+-\s+(\d+)\.\s+del$| ($1)|i;
    $ce->{subtitle} =~ s|\s+-\s+afsnit\s+(\d+)$| ($1)|i;
    $ce->{subtitle} =~ s|\s+-\s+osa\s+(\d+)$| ($1)|i;
    $ce->{subtitle} =~ s|\s+\(osa\s+(\d+)\)$| ($1)|i;
    $ce->{subtitle} =~ s|\s+Pt\s+(\d+)$| ($1)|;
  }

  # No Description
  if( ! $ce->{description} ){

    if( $ce->{title} =~ /\S+[a-z|0-9][A-Z]\S+/ ){
      my( $t, $d ) = ( $ce->{title} =~ /(.*\S+[a-z|0-9])([A-Z]\S+.*)/ );
      $ce->{title} = $t;
      $ce->{description} = $d;
    }

  }

  return;
}

sub isDate {
  my ( $text, $lang ) = @_;

#print "isDate: $lang >$text<\n";

  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){ # format '31/01/10'
    return 1;
  } elsif( $text =~ /^\d+-\S+-\d+$/i ){ # format '01-Feb-10'
    return 1;
  } elsif( $text =~ /^\d+\.\d+\.\d+$/i ){ # format '01.02.2010'
    return 1;
  } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){ # format 'MONDAY18 OCTOBER 2010'
    return 1;
  } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){ # format 'MONDAY18 OCTOBER 2010'
    return 1;
  } elsif( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+(Januari|Februari|Mars|April|Maj|Juni|Juli|Augusti|September|Oktober|November|December)\s+(\d+)$/i ){ # format 'M�ndag 11st Juli'
    return 1;
  } elsif( $text =~ /^\d+\s+(Januari|Februari|Mars|April|Maj|Juni|Juli|Augusti|September|Oktober|November|December)\s+(\d+)$/i ){ # format 'M�ndag 11st Juli'
    return 1;
  } elsif( $text =~ /^\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d+)$/i ){ # format 'M�ndag 11st Juli'
    return 1;
  } elsif( $text =~ /^\d+\s+(januar|februar|mars|april|mai|juni|juli|august|september|oktober|november|desember)\s+(\d+)$/i ){ # norweigan
    return 1;
  } elsif( $text =~ /^\d+\s+(tammikuu|helmikuu|maaliskuu|huhtikuu|toukokuu|kes.kuu|hein.kuu|elokuu|syyskuu|lokakuu|marraskuu|joulukuu)\s+(\d+)$/i ){ # finnish
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text, $lang, $filename ) = @_;

print "ParseDate: >$text<\n";

  my( $dayname, $day, $month, $monthname, $year );

  if( $lang =~ /^en$/ ){

    if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){ # try '31/01/10'
      ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{2})$/ );
    } elsif( $text =~ /^\d+-\S+-\d+$/i ){ # try '01-Feb-10'
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
      $month = MonthNumber( $monthname, "en" );
    } elsif( $text =~ /^\d+\.\d+\.\d+$/i ){ # try '01.02.2010'
      ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
    } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){
      ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(\d+)\s+(\S+)\s+(\d+)$/i );
      $month = MonthNumber( $monthname, "en" );
    } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){
      ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+(\d+)\s+(\S+)\s+(\d+)$/i );
      $month = MonthNumber( $monthname, "en" );
    } elsif( $text =~ /^\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s+(\S+)\s+(\d+)$/i );
      $month = MonthNumber( $monthname, "en" );
    }

  } elsif( $lang =~ /^no$/ ){
    if( $text =~ /^\d+\s*\D+\s*\d+$/i ){
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s*(\S+?)\s*(\d+)$/ );
      $month = MonthNumber( $monthname, "no" );
    }
  } elsif( $lang =~ /^da$/ ){
    if( $text =~ /^\d+\s*\D+\s*\d+$/i ){
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s*(\S+?)\s*(\d+)$/ );
      $month = MonthNumber( $monthname, "da" );
    }
  } elsif( $lang =~ /^sv$/ ){
    if( $text =~ /^\d+\s*\D+\s*\d+$/i ){
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s*(\S+?)\s*(\d+)$/ );
      $month = MonthNumber( $monthname, "sv" );
    }
  } elsif( $lang =~ /^fi$/ ){
    if( $text =~ /^\d+\s*\D+\s*\d+$/i ){
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\s*(\S+?)\s*(\d+)$/ );
      $month = MonthNumber( $monthname, "fi" );
    }
  } else {
    return undef;
  }

  #$year+= 2000 if $year< 100;
  my $currentyear = DateTime->today->year;
  my ($filenameyear) = ($filename =~ /(\d\d\d\d)/);

  if($year < 1950 or $year > $currentyear+2 ) {
    if(defined($filenameyear)) {
      $year = $filenameyear;
    } else {
      $year = $currentyear;
    }
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '4:00 Naughty Amateur Home Videos'
  if( $text =~ /^\d\d(:|\.)\d\d\s+.*$/i ){
    return 1;
  }

  return 0;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

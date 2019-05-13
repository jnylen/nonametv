package NonameTV::Importer::MindGeek;

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

use NonameTV qw/MyGet File2Xml norm MonthNumber Docxfile2Xml ParseXml ParseExcel formattedCell/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );

  # use augment
  #$self->{datastore}->{augment} = 1;

  $self->{datastorehelper} = $dsh;

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
  } elsif( $file =~ /.(xls|xlsx)$/i ) {
    $self->ImportXLS( $file, $chd );
  } elsif( $file =~ /.xml$/i ) {
    $self->ImportXML( $file, $chd );
  } else {
    error("unknown file: $file");
  }

}

sub ImportXML {
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  progress( "MindGeek: $xmltvid: Processing $file" );

  my $cref=`cat \"$file\"`;

  my $currdate = "x";

  $cref =~ s|
  ||g;
  $cref =~ s|mpeg7:||g;
  $cref =~ s|&|&amp;|g;

  #my $pre_string = '<?xml version="1.0" encoding="utf-8" standalone="yes"?><ProgramInformations>';
  #my $end_string = '</ProgramInformations>';

  #my $new_string = $pre_string.$cref.$end_string;

  my $doc = ParseXml(\$cref);
  
  if (not defined ($doc)) {
    error ("$file   : Failed to parse.");
    return 0;
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//ProgramInformation" );

  if( $ns->size() == 0 ) {
    error("No programs found");
    return 0;
  }

  foreach my $prog ($ns->get_nodelist) {
    my $start      = $self->parseTimestamp($prog->findvalue( 'ScheduleEvent/PublishedStartTime' ));
    my $end        = $self->parseTimestamp($prog->findvalue( 'ScheduleEvent/PublishedEndTime' ));

    my $title      = norm($prog->findvalue( 'BasicDescription/Title' ));
    my $desc       = norm($prog->findvalue( 'BasicDescription/Synopsis' ));
    my $genre      = norm($prog->findvalue( 'Genre' ));

    my $date = $start->ymd("-");
    if($date ne $currdate ) {
      	if( $currdate ne "x" ) {
			     # save last day if we have it in memory
		       #	FlushDayData( $channel_xmltvid, $dsh , @ces );
			     $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("MindGeek: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
    }

    my $ce =
    {
      channel_id  => $chd->{id},
      title       => norm($title),
      start_time  => $start->hms(":"),
      end_time    => $end->hms(":"),
    };

    # Desc
    $ce->{description} = norm($desc) if defined($desc);

    # Episode information
    my($season, $episode, $title2);
    if( $ce->{title} ){
      if( ($title2, $season, $episode) = ($ce->{title} =~ /(.*) S(\d+) EP(\d+)$/) ) {
        $ce->{title} = norm($title2);
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      } elsif( ($title2, $season, $episode) = ($ce->{title} =~ /(.*) S(\d+) EP (\d+)$/) ) {
        $ce->{title} = norm($title2);
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      } elsif( ($title2, $episode) = ($ce->{title} =~ /(.*) EP (\d+)$/) ) {
        $ce->{title} = norm($title2);
        $ce->{episode} = sprintf( " . %d .", $episode-1 );
      } elsif( ($title2, $episode) = ($ce->{title} =~ /(.*) (\d+)$/) ) {
        $ce->{title} = norm($title2);
        $ce->{episode} = sprintf( " . %d .", $episode-1 );
      }
    }

    progress( "MindGeek: $chd->{xmltvid}: $start - $ce->{title}" );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "MindGeek: $xmltvid: Processing $file" );
  my $date;
  my $currdate = "x";
  my %columns = ();

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "MindGeek: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "MindGeek: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;

    # go through the programs
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
            $columns{'Date'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Date$/i );
            $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Broadcast Time/i );
            $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Title$/i );
            $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Genre$/i );
            $columns{'Description'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Program Description$/i );

            $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /^Broadcast Time/i );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR), "en2", $file);
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			     # save last day if we have it in memory
		       #	FlushDayData( $channel_xmltvid, $dsh , @ces );
			     $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("MindGeek: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Title'}, $iR));
      my $start = ParseTime(formattedCell($oWkS, $columns{'Time'}, $iR));
      my $ep_desc = norm(formattedCell($oWkS, $columns{'Ep Synopsis'}, $iR));

      my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $start,
          description => norm($ep_desc)
      };

      progress( "MindGeek: $chd->{xmltvid}: $start - $title" );
      $dsh->AddProgramme( $ce );
    }

    $dsh->EndBatch( 1 );

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
    error( "MindGeek: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( "//w:p" );

  if( $rows->size() == 0 ) {
    error( "MindGeek: $chd->{xmltvid}: No Rows found" ) ;
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
    error( "MindGeek: $chd->{xmltvid} Unsupported language '$chd->{sched_lang}'" );
    return;
  }

  my $schedlang = $chd->{sched_lang};
  progress( "MindGeek: $chd->{xmltvid}: Setting schedules language to '$schedlang'" );

  #return if( $file !~ /\.doc$/i );

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = File2Xml( $file );
#print "DOC\n---------------\n" . $doc->toString(1) . "\n";
#return;


  if( not defined( $doc ) )
  {
    error( "MindGeek: $chd->{xmltvid} Failed to parse $file" );
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
    error( "MindGeek: $channel_xmltvid: No programme entries found in $filename" );
    return;
  }

  progress( "MindGeek: $channel_xmltvid: Processing $filename" );

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
	       error( "MindGeek: $channel_xmltvid: $filename Invalid date $text" );
      }
      progress("MindGeek: $channel_xmltvid: Date is: $date");

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
	       error( "MindGeek: $channel_xmltvid: State ST_START, found: $text" );
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

        progress("MindGeek: $channel_xmltvid: $start - $ce->{title}");

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
	      error( "MindGeek: $channel_xmltvid: $filename State ST_FDATE, found: $text" );
      }

    } elsif( $state == ST_EPILOG ){

      if( ($type != T_TEXT) and ($type != T_DATE) ) {

        error( "MindGeek: $channel_xmltvid: $filename State ST_EPILOG, found: $text" );

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

#print "ParseDate: >$text<\n";

  my( $dayname, $day, $month, $monthname, $year );

  if( $lang =~ /^en2$/ ){

    if( $text =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/i ){ # try '31/01/10'
      ( $month, $day, $year ) = ( $text =~ /^(\d{1,2})\/(\d{1,2})\/(\d{2})$/ );
    } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{2}$/i ){ # try '06-30-19'
      ( $month, $day, $year ) = ( $text =~ /^(\d{1,2})-(\d{1,2})-(\d{2})$/ );
    } elsif( $text =~ /^\d+-\S+-\d+$/i ){ # try '01-Feb-10'
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
      $month = MonthNumber( $monthname, "en" );
    }

  } elsif( $lang =~ /^en$/ ){

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

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp) = @_;

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
          time_zone => 'UTC'
        );
    };

    if ($@){
      w ("Could not convert time! Check for daylight saving time border. " . $year . "-" . $month . "-" . $day . " " . $hour . ":" . $minute);
      return undef;
    }

    #$dt->set_time_zone( 'UTC' );

    return( $dt );
  } else {
    return undef;
  }
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min, $secs, $ampm );

  if( $text =~ /^\[\d+\]:\d+/i ){
    ( $hour , $min ) = ( $text =~ /^\[(\d+)\]:(\d+)/ );
  } elsif($text =~ /^\d+:\d+$/i) {
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  } else {
    print Dumper($text);
  }

  if($hour >= 24) {
    $hour -= 24;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

package NonameTV::Importer::FOXTV;

use strict;
use warnings;

=pod

Import data from FOX

Channels: FOX (SWEDEN), FOX (NORWAY), Nat Geo Scandinavia & Iceland

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;
use XML::LibXML;
use Spreadsheet::ParseExcel;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm AddCategory AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{Timezone} = "Europe/Stockholm" unless defined $self->{Timezone};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, $self->{Timezone} );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;
  my $chanfileid = $chd->{grabber_info};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.(xls|xlsx)$/i ) {
    $self->ImportXLS( $file, $chd );
  } else {
    error( "FOXTV: Unknown file format: $file" );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "FOXTV: $file: Failed to parse xml" );
    return;
  } else {
    progress("Processing $file");
  }

  my $currdate = "x";
  my $column;

  my $rows = $doc->findnodes( "//Event" );

  if( $rows->size() == 0 ) {
    error( "FOXTV: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($dummy, $week, $year, $meh);
  ($dummy, $week, $year) = ($file =~ /(wk|uke|week)\s*(\d+)_(\d+)/i);
  ($year, $dummy, $week) = ($file =~ /(\d\d\d\d)_(wk|uke|week)\s*(\d+)/i) if (!defined $week);
  ($dummy, $meh, $week) = ($file =~ /(wk|uke|week)(\s*|_|)(\d+)/i) if(!defined $year);

  if(!defined $year) {
    error( "FOXTV: $chd->{xmltvid}: Failure to get year from filename, grabbing current year" ) ;
    $year = (localtime)[5] + 1900;
    #return;
  } else { $year += 2000; }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  foreach my $row ($rows->get_nodelist) {
    my($day, $month, $year, $date);
    my $title_lang = norm($row->findvalue( 'ProgrammeTitle' ) ) if norm($row->findvalue( 'ProgrammeTitle' ) ) ne "-";
    my $title_org = norm($row->findvalue( 'OriginalTitle' ) ) if norm($row->findvalue( 'OriginalTitle' ) ) ne "-";
    my $title = $title_lang || $title_org;

    my $start = $row->findvalue( 'StartTime' );
    ($day, $month, $year) = ($row->findvalue( 'Date' ) =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)$/);
    $date = $year."-".$month."-".$day;
	  if($date ne $currdate ) {
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("FOXTV: Date is: $date");
    }

    my $hd = norm($row->findvalue( 'HighDefinition' ) );
    my $ws = norm($row->findvalue( 'Formatwidescreen' ) );
    my $yr = norm($row->findvalue( 'YearOfRelease' ));
    my $ep_desc  = norm($row->findvalue( 'episodesynopsis' ) );
    my $se_desc  = norm($row->findvalue( 'seasonsynopsis' ) );
    my $subtitle = norm($row->findvalue( 'EpisodeTitle' ) );
    my $ep_num   = norm($row->findvalue( 'EpisodeNumber' ) );
    my $se_num   = norm($row->findvalue( 'SeasonNumber' ) );
    my $of_num   = norm($row->findvalue( 'NumberofepisodesintheSeason' ) );
    my $genre    = norm($row->findvalue( 'Longline' ) );
    my $prodcountry = norm($row->findvalue( 'productioncountry' ) );
    my $actors = $row->findvalue( 'Actors' );
    $actors =~ s/-$//g;
    $actors =~ s/, /;/g;
    $actors =~ s/;$//g;
    $actors =~ s/,$//g;
    my $directors = $row->findvalue( 'Directors' );
    $directors =~ s/, /;/g;
    $directors =~ s/-$//g;
    $directors =~ s/;$//g;
    $directors =~ s/,$//g;

    my $desc;
    $desc = $ep_desc;
    $desc = $se_desc if !defined($ep_desc) or norm($ep_desc) eq "" or norm($ep_desc) eq "null" or norm($ep_desc) eq "1";
    my $premiere    = norm($row->findvalue( 'Premiere' ) );

    my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start,
        description => norm($desc)
    };

    if( defined( $yr ) and ($yr =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    # Aspect
    if($ws eq "Yes")
    {
      $ce->{aspect} = "16:9";
    } else {
      $ce->{aspect} = "4:3";
    }

    # HDTV & Actors
    $ce->{quality} = 'HDTV' if ($hd eq 'Yes');
    $ce->{actors} = norm($actors) if($actors ne "" and $actors ne "null");
    $ce->{directors} = norm($directors) if($directors ne "" and $directors ne "null");
    $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "" and $subtitle ne "null";

    # Episode info in xmltv-format
    if( ($ep_num ne "0" and $ep_num ne "" and $ep_num ne "-") and ( $of_num ne "0" and $of_num ne "" and $of_num ne "-") and ( $se_num ne "0" and $se_num ne "" and $se_num ne "-") )
    {
        $ce->{episode} = sprintf( "%d . %d/%d .", $se_num-1, $ep_num-1, $of_num );
    }
    elsif( ($ep_num ne "0" and $ep_num ne "" and $ep_num ne "-") and ( $of_num ne "0" and $of_num ne "" and $of_num ne "-") )
    {
      	$ce->{episode} = sprintf( ". %d/%d .", $ep_num-1, $of_num );
    }
    elsif( ($ep_num ne "0" and $ep_num ne "" and $ep_num ne "-") and ( $se_num ne "0" and $se_num ne "" and $se_num ne "-") )
    {
        $ce->{episode} = sprintf( "%d . %d .", $se_num-1, $ep_num-1 );
    }
    elsif( $ep_num ne "0" and $ep_num ne "" and $ep_num ne "-" )
    {
        $ce->{episode} = sprintf( ". %d .", $ep_num-1 );
    }

    my ( $program_type, $category ) = $self->{datastore}->LookupCat( "FOXTV", $genre );
    AddCategory( $ce, $program_type, $category );

    my ( $country ) = $self->{datastore}->LookupCountry( "FOXTV", $prodcountry );
    AddCountry( $ce, $country );

    # Original title
    $title_org =~ s/(Series |Y)(\d+)$//i;
    $title_org =~ s/$se_num//i;
    if(defined($title_org) and norm($title_org) =~ /, The$/i)  {
        $title_org =~ s/, The//i;
        $title_org = "The ".norm($title_org);
    }
    $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

    if( $premiere eq "Premiere" )
    {
      $ce->{new} = "1";
    }
    else
    {
      $ce->{new} = "0";
    }

    progress( "FOXTV: $chd->{xmltvid}: $start - $title" );
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
  progress( "FOXTV: $xmltvid: Processing $file" );
  my $date;
  my $currdate = "x";
  my %columns = ();

  my $oBook;
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Ginx: Processing worksheet: $oWkS->{Name}" );

    my $foundcolumns = 0;
    my $i = 0;

    # go through the programs
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Date$/ );

            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Start Time$/ );

            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Program Title$/ );

            $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Original Title$/ );
            $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Original Program Title$/ );

            $columns{'Ser No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season Number/ );
            $columns{'Ser Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season Synopsis/ );

            $columns{'Ep No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Number/ );
            $columns{'Ep Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Episode Title/ );
            $columns{'Ep TitleORG'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Original Episode Title/ );
            $columns{'Ep Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Synopsis/ );
            $columns{'Eps'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Number of episodes in the Season/ );

            $columns{'Genre'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Longline/ );

            $columns{'Country'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Production Country/ );
            $columns{'Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Year Of Release/ );
            $columns{'Actors'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Actors/ );
            $columns{'Directors'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Director\/s/ );

            $columns{'HD'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /High Definition/ );
            $columns{'169'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /16:9 Format/ );
            $columns{'Premiere'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Premiere/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate($oWkC->Value);
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
        progress("FOXTV: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
  	  $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $start = $oWkC->Value if( $oWkC->Value );

      # title
      my $title_field = int2col($columns{'Title'}).$i;
      my $title_lang = norm($ref->[1]{$title_field}) if norm($ref->[1]{$title_field}) ne "-";

      my $title_org = norm($oWkS->{Cells}[$iR][$columns{'ORGTitle'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'ORGTitle'}]);

      my $title = $title_lang || $title_org;


      my $hd = norm($oWkS->{Cells}[$iR][$columns{'HD'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'HD'}]);
      my $ws = norm($oWkS->{Cells}[$iR][$columns{'169'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'169'}]);
      my $yr = norm($oWkS->{Cells}[$iR][$columns{'Year'}]->Value) if defined($oWkS->{Cells}[$iR][$columns{'Year'}]);

      my $ep_field = int2col($columns{'Ep Synopsis'}).$i;
      my $ep_desc = $ref->[1]{$ep_field};

      my $se_field = int2col($columns{'Ser Synopsis'}).$i;
      my $se_desc = $ref->[1]{$se_field};

      my $subtitle = norm($oWkS->{Cells}[$iR][$columns{'Ep Title'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Ep Title'}]) and norm($oWkS->{Cells}[$iR][$columns{'Ep Title'}]->Value ) ne "-";
      my $ep_num   = norm($oWkS->{Cells}[$iR][$columns{'Ep No'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Ep No'}]);
      my $se_num   = norm($oWkS->{Cells}[$iR][$columns{'Ser No'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Ser No'}]);
      my $of_num   = norm($oWkS->{Cells}[$iR][$columns{'Eps'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Eps'}]);
      my $genre    = norm($oWkS->{Cells}[$iR][$columns{'Genre'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Genre'}]);
      my $prodcountry = norm($oWkS->{Cells}[$iR][$columns{'Country'}]->Value ) if defined($oWkS->{Cells}[$iR][$columns{'Country'}]);
      my $actors = $oWkS->{Cells}[$iR][$columns{'Actors'}]->Value if defined($oWkS->{Cells}[$iR][$columns{'Actors'}]);
      $actors =~ s/, /;/g;
      $actors =~ s/-$//g;
      $actors =~ s/;$//g;
      $actors =~ s/,$//g;
      my $directors = $oWkS->{Cells}[$iR][$columns{'Directors'}]->Value if defined($oWkS->{Cells}[$iR][$columns{'Directors'}]);
      $directors =~ s/, /;/g;
      $directors =~ s/-$//g;
      $directors =~ s/;$//g;
      $directors =~ s/,$//g;

      my $desc;
      $desc = $ep_desc if(defined($ep_desc));
      $desc = $se_desc if !defined($ep_desc) and defined($se_desc) or norm($ep_desc) eq "" or norm($ep_desc) eq "-" or norm($ep_desc) eq "1";
      $desc = "" if $desc eq "" or $desc eq "-" or $desc eq "\x{2d}" or $desc eq "1";

      my $premiere = norm($oWkS->{Cells}[$iR][$columns{'Premiere'}]->Value );

      my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $start,
          description => norm($desc)
      };

      if( defined( $yr ) and ($yr =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      # Aspect
      if(defined($ws) and $ws eq "Yes")
      {
        $ce->{aspect} = "16:9";
      } else {
        $ce->{aspect} = "4:3";
      }

      # HDTV & Actors
      $ce->{quality} = 'HDTV' if (defined($hd) and $hd eq 'Yes');
      $ce->{actors} = norm($actors) if($actors ne "" and $actors ne "null");
      $ce->{directors} = norm($directors) if($directors ne "" and $directors ne "null");
      $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "" and $subtitle ne "null";

      # Episode info in xmltv-format
      if( (defined($ep_num) and defined($se_num) and defined($of_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "") and ( $of_num ne "\x{2d}" and $of_num ne "") and ( $se_num ne "\x{2d}" and $se_num ne "") )
      {
          $ce->{episode} = sprintf( "%d . %d/%d .", $se_num-1, $ep_num-1, $of_num );
      }
      elsif( (defined($ep_num) and defined($of_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "") and ( $of_num ne "\x{2d}" and $of_num ne "") )
      {
          $ce->{episode} = sprintf( ". %d/%d .", $ep_num-1, $of_num );
      }
      elsif( (defined($ep_num) and defined($se_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "") and ( $se_num ne "\x{2d}" and $se_num ne "") )
      {
          $ce->{episode} = sprintf( "%d . %d .", $se_num-1, $ep_num-1 );
      }
      elsif( defined($ep_num) and $ep_num ne "\x{2d}" and $ep_num ne "" )
      {
          $ce->{episode} = sprintf( ". %d .", $ep_num-1 );
      }

      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "FOXTV", $genre );
      AddCategory( $ce, $program_type, $category );

      if($prodcountry ne "-" and $prodcountry ne "\x{2d}") {
        my ( $country ) = $self->{datastore}->LookupCountry( "FOXTV", $prodcountry );
        AddCountry( $ce, $country );
      }

      # Original title
      $title_org =~ s/(Series |Y)(\d+)$//i;
      $title_org =~ s/$se_num//i if defined $se_num;
      if(defined($title_org) and norm($title_org) =~ /, The$/i)  {
          $title_org =~ s/, The//i;
          $title_org = "The ".norm($title_org);
      }
      $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

      if( $premiere eq "Premiere" )
      {
        $ce->{new} = "1";
      }
      else
      {
        $ce->{new} = "0";
      }

      progress( "FOXTV: $chd->{xmltvid}: $start - $title" );
      $dsh->AddProgramme( $ce );
    }

    $dsh->EndBatch( 1 );

  }

}

sub ParseDate {
  my( $text ) = @_;

  my( $month, $day, $year );

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d\d\d\d$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d\d\d\d)$/ );
  }

  if(not defined($year)) {
    return undef;
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

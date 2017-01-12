package NonameTV::Importer::Trace;

use strict;
use warnings;

=pod

Import data from xls files delivered via e-mail.

Channel: www.trace.tv

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use Spreadsheet::ParseExcel;
use DateTime::Format::Excel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Trace XLS: $chd->{xmltvid}: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  if( not defined( $oBook ) ) {
    error( "Trace XLS: $file: Failed to parse xls" );
    return;
  }

  my $gmt = "no";

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    my $foundcolumns = 0;


    if( $oWkS->{Name} =~ /^GMT/ ){
      $gmt = "true";
    }

    if( $gmt eq "true" and $oWkS->{Name} !~ /^GMT \+1$/ and $oWkS->{Name} !~ /^GMT\+1$/ ){
      progress("Trace XLS: $chd->{xmltvid}: skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("Trace XLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    my $i = 0;

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      if( not %columns ){

        # the column names are stored in the 5th row
        # so read them and store their column positions
        # for further findvalue() calls
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            my $column_name = norm($oWkS->{Cells}[$iR][$iC]->Value);
            print("$iC - '$column_name'\n");

            $columns{'Title'} = $iC if( $column_name =~ /^programmeName$/i );
            $columns{'Title'} = $iC if( $column_name =~ /^Programme Name$/i );
            $columns{'Title'} = $iC if( $column_name =~ /^﻿Programme Title$/i );
            $columns{'Title'} = $iC if( $column_name =~ /^Program Title$/i );
            $columns{'Title'} = $iC if( $column_name =~ /^Nom du programme/i );
            $columns{'Title'} = $iC if( !defined($columns{'Title'}) and $column_name eq "" );

            $columns{'EpTitle'} = $iC if( $column_name =~ /^Episode Title$/i );
            $columns{'Date'} = $iC if( $column_name =~ /^Programme Start Date$/i );
            $columns{'Date'} = $iC if( $column_name =~ /^Date$/i );
            $columns{'Date'} = $iC if( $column_name =~ /^Date de diffusion$/i );
            $columns{'Time'} = $iC if( $column_name =~ /Programme Start Time/i );
            $columns{'Time'} = $iC if( $column_name =~ /^Start Time/i );
            $columns{'Time'} = $iC if( $column_name =~ /Programme Start$/i );
            $columns{'Time'} = $iC if( $column_name =~ /^Heure de diffusion$/i );
            $columns{'Duration'} = $iC if( $column_name =~ /Programme Duration/i );
            $columns{'Duration'} = $iC if( $column_name =~ /Durée/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /Programme Synopsis Txt ENG/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /Programme Synopsis Txt$/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /^Synopsis$/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /^EPG Synopsis$/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /^EPG sysnopsis$/i );
            $columns{'Synopsis'} = $iC if( $column_name =~ /^Synopsis du Programme$/i );
            $columns{'EpNum'} = $iC if( $column_name =~ /^Episode Number$/i );
            $columns{'EpsNum'} = $iC if( $column_name =~ /^Episodes in the season$/i );
            $columns{'Rating'} = $iC if( $column_name =~ /^PG Rating$/i );
            $columns{'Rating'} = $iC if( $column_name =~ /^Rating$/i );
            $columns{'Rating'} = $iC if( $column_name =~ /^Programme Rating$/i );
            $columns{'Genre'} = $iC if( $column_name =~ /^Genre$/i );

            $foundcolumns = 1 if( $column_name =~ /Date/i );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      print Dumper(%columns);

      # Date
      next if( !defined($columns{'Date'}) );
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $date = ExcelFmt('yyyy-MM-dd', $oWkC->Value);
      next if( ! $date );

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ExcelFmt('hh:mm', $oWkC->{Val});

      # Duration
      my $duration = undef;
      if(defined($columns{'Duration'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'Duration'}];
        $duration = ExcelFmt('hh:mm', $oWkC->{Val});
      }

      # Parse
      my( $start_dt , $end_dt ) = create_dt( $date , $time , $duration );

      # Create date
      if( $start_dt->ymd("-") ne $currdate ) {
        if( $currdate ne "x" ) {
	         $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $start_dt->ymd("-");
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $start_dt->ymd("-") , "06:00" );
        $currdate = $start_dt->ymd("-");

        progress("Trace XLS: $chd->{xmltvid}: Date is: " . $start_dt->ymd("-"));
      }

      # Title
      next if( !defined($columns{'Title'}) );
      my $title_field = int2col($columns{'Title'}).$i;
      my $title = $ref->[$iSheet+1]{$title_field};

      print Dumper($title);

      # Rating
      if(defined($columns{'Rating'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'Rating'}];
        next if( ! $oWkC );
        my $rating = $oWkC->Value;
      }

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $start_dt->hms(":"),
      };

      $ce->{end_time} = $end_dt->hms(":") if defined($end_dt);

      # Synopsis
      if(defined($columns{'Synopsis'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
        my $synopsis_field = int2col($columns{'Synopsis'}).$i;
        my $synopsis = $ref->[$iSheet+1]{$synopsis_field};
        $ce->{description} = norm($synopsis) if $synopsis;
      }

      # EpTitle
      if(defined($columns{'EpTitle'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'EpTitle'}];
        my $subtitle_field = int2col($columns{'EpTitle'}).$i;
        my $subtitle = $ref->[$iSheet+1]{$subtitle_field};
        $ce->{subtitle} = norm($subtitle) if $subtitle;
      }

      # Episodes
      if(defined($columns{'EpNum'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'EpNum'}];
        my $episode = $oWkC->Value;

        # Eps
        if(defined($columns{'EpsNum'})) {
          $oWkC = $oWkS->{Cells}[$iR][$columns{'EpsNum'}];
          my $episodes = $oWkC->Value;
          $ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $episodes );
        } else {
          $ce->{episode} = sprintf( " . %d . ", $episode-1 );
        }
      }

      if(defined($columns{'Genre'})) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
        my $genre_field = int2col($columns{'Genre'}).$i;
        my $genre = $ref->[$iSheet+1]{$genre_field};

        my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Trace", $genre );
        #AddCategory( $ce, $program_type, $category );
      }

      print Dumper($ce);

      progress( "Trace XLS: $chd->{xmltvid}: $start_dt - $title" );

      $dsh->AddProgramme( $ce );

    } # next row

    undef %columns;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub create_dt
{
  my( $date, $time , $du ) = @_;
  return undef if(!$date or !$time);

  print("$date - $time - $du\n");

  my( $day, $month, $year );

  # Format '2010-03-31'
  if( $date =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $date =~ /^(\d+)-(\d+)-(\d+)$/ );
  # Format 'DD/MM/YY'
  } elsif( $date =~ /^\d+\/\d+\/\d+$/ ){
    ( $day, $month, $year ) = ( $date =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  # Format 'MM-DD-YY'
  } elsif( $date =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $date =~ /^(\d+)-(\d+)-(\d+)$/ );
  # Format '40179' - Excel date format
  } elsif( $date =~ /^\d{5}$/ ){
    my $dt = DateTime::Format::Excel->parse_datetime( $date );
    $year = $dt->year;
    $month = $dt->month;
    $day = $dt->day;
  }

  return undef if not $year;

  # start time
  my ( $hour , $minute ) = ( $time =~ /^(\d+)\:(\d+)/ );
  my $sdt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Paris',
                           );
  # times are in CET timezone in original file
  #$sdt->set_time_zone( "UTC" );

  # end time
  my $edt = undef;
  if($du and $du =~ /\:/) {
    my ( $duhour , $duminute ) = ( $du =~ /^(\d+)\:(\d+)/ );
    $edt = $sdt->clone->add( hours => $duhour, minutes => $duminute );
  }

  return( $sdt, $edt );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

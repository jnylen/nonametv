package NonameTV::Importer::Bloomberg;

use strict;
use warnings;

=pod

Imports data from XLSX files for the Bloomberg station.

The importer is hard coded for Pan Europe.
Numbers for different countries:
UK Title: 0
UK Time: 1
Pan EU and Africa: 2
CET: 3
Middle East: 4
ME Time: 5

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "CET" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xls|xlsx)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "High: Unknown file format: $file" );
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
  my @ces;

  progress( "Bloomberg: Processing flat XLS $file" );

  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Bloomberg: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # Parse monthname and day
    if(my($day, $dumbcat, $monthname) = ($oWkS->{Name} =~ /(\d+)( |-)(.*?)$/)) {
      my $month = MonthNumber($monthname, "en");
      my $year = DateTime->now->year();
      if($monthname eq "January") {
        $year = $year + 1;
      }

      my $date = sprintf("%d-%02d-%02d", $year, $month, $day);

      # Startdate
      if( defined($date) and $date !~ /^19/ and $date ne $currdate ) {
        if( $currdate ne "x" ) {
          # save last day if we have it in memory
          #	FlushDayData( $channel_xmltvid, $dsh , @ces );
          $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Bloomberg: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

    }

		my $foundcolumns = 0;
    %columns = ();

    my $oldtime = undef;

    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Pan Europe/i );
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^CET/ or $oWkS->{Cells}[$iR][$iC]->Value =~ /^CEST/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^CET/ or $oWkS->{Cells}[$iR][$iC]->Value =~ /^CEST/ );
          }

        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }


      # title
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      $title =~ s/&lt;//;
      $title =~ s/&gt;//;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ExcelFmt('hh:mm', $time);

      # if its blank then minute is 30
      if(!defined($time) or norm($time) eq "") {
        next if !defined($oldtime);
        my( $newhour , $newmin ) = ( $oldtime =~ /^(\d+):(\d+)$/ );
        $newmin = 30;

        $time = sprintf( "%02d:%02d", $newhour, $newmin );
      }

      $oldtime = $time;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
      };

      # subtitle
      if( my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/) ) {
        $ce->{title} = norm($t);
        $ce->{subtitle} = norm($st);
      }

      # episode & season
      my($seas, $eps);
      if( ( $seas, $eps ) = ($ce->{title} =~ /S(\d+) ep (\d+)$/i) ) {
        $ce->{title} =~ s/S(\d+) ep (\d+)$//i;
        $ce->{episode} = sprintf( "%d . %d .", $seas-1, $eps-1 );
      } elsif( ( $eps ) = ($ce->{title} =~ /ep (\d+)$/i) ) {
        $ce->{title} =~ s/ep (\d+)$//i;
        $ce->{episode} = sprintf( ". %d .", $eps-1 );
      } elsif( ( $eps ) = ($ce->{title} =~ /\(ep\. (\d+)\)$/i) ) {
        $ce->{title} =~ s/\(ep\. (\d+)\)$//i;
        $ce->{episode} = sprintf( ". %d .", $eps-1 );
      }

      $ce->{title} =~ s/\(TAPED\/NOT TO BE CONFUSED WITH "BEST OF"\)$//i;

      # norm it
      $ce->{title} = norm($ce->{title});
      progress("BBCWW: $chd->{xmltvid}: $time - $ce->{title}");

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );

  # format '1/14/2012'
  } elsif( $text =~ /^\d+\/\d+\/\d{4}$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i );
  }


  $year += 2000 if $year < 100;


return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

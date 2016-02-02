package NonameTV::Importer::FightSports;

use strict;
use warnings;

=pod
Importer for FightSports

Channels: FIGHT SPORTS EU (SPAIN, EX YUGO), FIGHT SPORTS FSF (Scandinavia, FR, Baltics)

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm normLatin1 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error /;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "FightSports: Unknown file format: $file" );
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
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # process
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    progress( "FightSports: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      # date - column 1
      my $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      $date = ParseDate( ExcelFmt('yyyy-mm-dd', $oWkC->{Val}) );

      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			       $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("FightSports: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time - column 2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ExcelFmt('hh:mm', $time);

      # duration - column 3

      # title - column 4
      $oWkC = $oWkS->{Cells}[$iR][4];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # episode title - column 5
      $oWkC = $oWkS->{Cells}[$iR][5];
      my $eptitle = $oWkC->Value if( $oWkC->Value );

      # season - column 6
      $oWkC = $oWkS->{Cells}[$iR][6];
      my $season = $oWkC->Value if( $oWkC );

      # episode - column 7
      $oWkC = $oWkS->{Cells}[$iR][7];
      my $episode = $oWkC->Value if( $oWkC );

      # category - column 8
      $oWkC = $oWkS->{Cells}[$iR][8];
      my $cate = $oWkC->Value if( $oWkC );

      # ep title v2? - column 9

      # description - column 10
      $oWkC = $oWkS->{Cells}[$iR][10];
      my $desc = $oWkC->Value if( $oWkC );

      my $ce = {
        channel_id  => $chd->{channel_id},
        start_time  => $time,
        title       => normLatin1($title),
        description => normLatin1($desc)
      };

      # Extra info
      $ce->{subtitle} = normLatin1($eptitle) if defined $eptitle;

      # category
      if( $cate and $cate ne "" ) {
  			my($program_type, $category ) = $ds->LookupCat( 'FightSports', $cate );
  			AddCategory( $ce, $program_type, $category );
  		}

      # Episode data info
      if($episode ne "" and $season ne "")
  		{
  			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
  		}

      progress("FightSports: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  #print("text: $text\n");

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

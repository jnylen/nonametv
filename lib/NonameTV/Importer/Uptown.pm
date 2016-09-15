package NonameTV::Importer::Uptown;

use strict;
use warnings;

=pod
Importer for Uptown TV AS

Channels: Uptown Classic

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
my $converter = Text::Iconv -> new ("utf-8", "latin1");

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xlsx|xls)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Uptown: Unknown file format: $file" );
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

  progress( "Uptown: $chd->{xmltvid}: Processing $file" );
  if ( $file =~ /\.(xlsx|xlsm)$/i ){ $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  #my $ref = ReadData ($file);

  # fields
  my $num_date = 9;
  my $num_time = 10;
  my $num_title = 2;
  my $num_subtitle = 1;
  my $num_prodyear = 6;

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Uptown: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    my $i = 3;
    for(my $iR = 3 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$num_date];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
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
        progress("Uptown: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$num_time];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ExcelFmt('hh:mm', $time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][$num_title];
      next if( ! $oWkC );
      my $title = $oWkC->{Val} if( $oWkC->{Val} );

      # subtitle
      $oWkC = $oWkS->{Cells}[$iR][$num_subtitle];
      my $subtitle = $oWkC->{Val} if( $oWkC->{Val} );

      # Extra
      my $year = $oWkS->{Cells}[$iR][$num_prodyear]->Value if $oWkS->{Cells}[$iR][$num_prodyear];

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        subtitle => norm( $subtitle )
      };

      # Episode number
      my ( $epnum ) = ($ce->{title} =~ /Ep\.\s*(\d+)$/i );
      if(defined($epnum)) {
        $ce->{episode} = sprintf( ". %d .", $epnum-1 );
        $ce->{program_type} = "series";

        $ce->{title} =~ s/Ep\.\s*(\d+)$//i;
        $ce->{title} = norm($ce->{title});
      }

      progress("Uptown: $chd->{xmltvid}: $time - $ce->{title}");

      $dsh->AddProgramme( $ce );
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

  if( $text =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/ );
  } elsif( $text =~ /^(\d\d)-(\d\d)-(\d\d\d\d)/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d\d)-(\d\d)-(\d\d\d\d)/ );
  }

  return undef if !defined($year);
  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );

  return join( ";", grep( /\S/, @persons ) );
}

1;

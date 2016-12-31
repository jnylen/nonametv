package NonameTV::Importer::Highview;

use strict;
use warnings;

=pod

Imports data from Highview, specifically RCK and DELUXE MUSIC.
The lists is in XML format and XLSX. Every day is handled as a seperate batch.

Planet TV is handled in another Importer called PlanetTV.pm.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;

use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm ParseXml AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  # use augment
  #$self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLSX( $file, $chd );
  } elsif( $file =~ /\.xml$/i ) {
    $self->ImportXML( $file, $chd );
  }

  return;
}

sub ImportXLSX
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Highview: $chd->{xmltvid}: Processing $file" );

  my $oBook;
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  my $ref = ReadData ($file);

  my($iR, $oWkS, $oWkC);

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
	   my $foundcolumns = 0;

     my $i = 0;

     for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
       $i++;

       if( not %columns ){
         # the column names are stored in the first row
         # so read them and store their column positions
         # for further findvalue() calls

         for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
           if( $oWkS->{Cells}[$iR][$iC] ){
             $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Sendung/ );
             $columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Beginn/ );
             $columns{'Stop'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Ende/ );
             $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Datum/ );

             $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Beginn/ ); # Only import if season number is found
           }

         }

         %columns = () if( $foundcolumns eq 0 );

         next;
       }

       # date (column 1)
       $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
       my $date = ExcelFmt('yyyy:mm:dd', $oWkC->Value);

       # time (column 1)
       $oWkC       = $oWkS->{Cells}[$iR][$columns{'Start'}];
       my $start   = ParseDateTime( $date . "T" . ExcelFmt('hh:mm:ss', $oWkC->{Val}) );
       $date       = $start->ymd("-");

       next if(!$date);

       if($date ne $currdate ) {
         if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
         }

         my $batchid = $chd->{xmltvid} . "_" . $date;
         $dsh->StartBatch( $batchid , $chd->{id} );
         $dsh->StartDate( $date , "06:00" );
         $currdate = $date;

         progress("Highview: Date is: $date");
       }

       #$oWkC = $oWkS->{Cells}[$iR][$columns{'Stop'}];
       #my $stop = ParseTime( $oWkC->Value );

       # program_title (column 4)
       # title
       my $title_field = int2col($columns{'Title'}).$i;
       my $title = $ref->[1]{$title_field};

       my $ce = {
         channel_id   => $chd->{id},
         title		   => norm($title),
         start_time   => $start->hms(":"),
       };

       progress("$start - $title");
       $dsh->AddProgramme( $ce );

     }
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "Highview: $chd->{xmltvid}: Processing XML $file" );

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns="urn:tva:metadata:2002"||;
  $cref =~ s| xmlns="urn:tva:metadata:2012"||;
  $cref =~ s| xmlns:mpeg7="urn:tva:mpeg7:2008"||;
  $cref =~ s| xmlns:dtag="urn:dtag:metadata:extended:2012"||;
  $cref =~ s| xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"||;
  $cref =~ s| xsi:schemaLocation="urn:tva:metadata:2012 tva_metadata_3-1_v181.xsd urn:tva:mpeg7:2008 tva_mpeg7_2008.xsd urn:dtag:metadata:extended:2012 dtag_metadata_2012.xsd"||;
  $cref =~ s| xsi:schemaLocation="urn:tva:metadata:2002 dataimport/tva_metadata_v13.xsd"||;
  $cref =~ s| xml:lang="en"||;
  $cref =~ s| xml:lang="de"||;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if( not defined( $doc ) ) {
    error( "Highview: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;
  my %programs;

  # the grabber_data should point exactly to one worksheet
  my $pis = $doc->findnodes( ".//ProgramInformation" );

  if( $pis->size() == 0 ) {
      error( "Highview: No ProgramInformation found" ) ;
      return;
  }

  foreach my $pi ($pis->get_nodelist) {
    my $pid = $pi->findvalue( './@programId' );

    my $p = {
      title          => norm($pi->findvalue( './/BasicDescription//Title' )),
      genre          => norm($pi->findvalue( './/Genre[@type="main"]//Name' )),
    };

    $programs{$pid} = $p;
  }

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//ScheduleEvent" );

  if( $rows->size() == 0 ) {
      error( "Highview: No Rows found" ) ;
      return;
  }

  # Batch id
  foreach my $row ($rows->get_nodelist) {
    my $program_id = $row->findvalue( './/Program/@crid' );
    my $start      = ParseDateTime($row->findvalue( './/PublishedStartTime' ));
    my $stop       = ParseDateTime($row->findvalue( './/PublishedEndTime' ));
    my $date       = $start->ymd("-");

    my $pd         = $programs{$program_id};
    my $title      = $pd->{title};

    ## Batch
  	if($date ne $currdate ) {
      if( $currdate ne "x" ) {
          # save last day if we have it in memory
          #	FlushDayData( $channel_xmltvid, $dsh , @ces );
          $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("Highview: Date is: $date");
  	}

    my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->hms(":"),
    };

    progress( "Highview: $start - ".norm($ce->{title}) );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "Europe/Berlin"
  );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

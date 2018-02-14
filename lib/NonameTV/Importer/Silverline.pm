package NonameTV::Importer::Silverline;

use strict;
use warnings;

=pod
Importer for Silverline

Every day is runned as a seperate batch.

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
    error( "Silverline: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  # Depending on what timezone
  my $dsh = undef;
  if($chd->{grabber_info} ne "") {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  } else {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  }
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Silverline: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

	  my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

      			$columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Datum/ );
            $columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Startzeit/ );
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Titel/ );
            $columns{'Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Produktionsjahr/ );
            $columns{'ProductionCountry'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Produktionsland/ );
            $columns{'Directors'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Regie/ );
            $columns{'Cast'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Darsteller/ );
            $columns{'IMDB'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^IMDb/ );
            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Synopsis/ );


            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Datum/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
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
        progress("Silverline: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	    # time
	    $oWkC = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      $time =~ s/'//g;

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

	    # extra info
	    my $desc = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
	    my $year = $oWkS->{Cells}[$iR][$columns{'Year'}]->Value if defined($columns{'Year'}) and $oWkS->{Cells}[$iR][$columns{'Year'}];

      progress("Silverline: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
        program_type => "movie"
      };

      # Extra
  	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Cast'}]->Value))          if defined($columns{'Cast'}) and $oWkS->{Cells}[$iR][$columns{'Cast'}];
  	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Directors'}]->Value))      if defined($columns{'Directors'}) and $oWkS->{Cells}[$iR][$columns{'Directors'}];
  	  $ce->{presenters}      = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Presenter'}]->Value))     if defined($columns{'Presenter'}) and $oWkS->{Cells}[$iR][$columns{'Presenter'}];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      $dsh->AddProgramme( $ce );
    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\.\d+\.\d+$/ ) { # format '07.09.2017'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;

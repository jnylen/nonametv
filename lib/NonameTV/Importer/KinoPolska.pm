package NonameTV::Importer::KinoPolska;

use strict;
use warnings;

=pod
Importer for Kino Polska

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1257");

use Spreadsheet::ParseXLSX;
#use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Encode::Detect::Detector;

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

  if( $file =~ /\.(xlsx|xls)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "KinoPolska: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  # Depending on what timezone
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";


  my $oBook = Spreadsheet::ParseXLSX->new->parse($file);

  # worksheets
  for my $oWkS ( $oBook->worksheets() ) {
    my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            #$columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;
            $columns{'Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Tytuł$/i );
			$columns{'Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Title$/i );
			$columns{'Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Local Title$/i );
			$columns{'Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Cykl programu/i );

			$columns{'ORGTitle'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^ORIGINAL TITLE$/i );

            $columns{'Episode Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Tytuł odcinka$/i );
            $columns{'Episode Title'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Tytuł programu/i );

            $columns{'Date'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Data$/i );
            $columns{'Title'} = 2 if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Data$/i );
            $columns{'Date'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Start date$/i );
            $columns{'Date'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Date$/i );
            $columns{'Time'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Godzina$/i );
            $columns{'Time'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Start time$/i );
            $columns{'DateTime'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Data i godzina emisji/i );

            $columns{'Year'}      = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /Rok produkcji/i );
            $columns{'Year'}      = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Year$/i );
            $columns{'Director'}  = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Reżyser$/i );
            $columns{'Director'}  = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Director$/i );
            $columns{'Cast'}      = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Obsada$/i );
            $columns{'Cast'}      = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Casting$/i );

            $columns{'Synopsis'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Opis$/i );
            $columns{'Synopsis'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Synopsis$/i );
            $columns{'Synopsis'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Synopsis CZ$/i );
            $columns{'Synopsis'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Synopsis ROM$/i );
            $columns{'Synopsis'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Opis \(synopsis\)$/i );

            $foundcolumns = 1 if( defined($columns{'Date'}) or defined($columns{'DateTime'}) );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      my ($oWkC, $time);

      # Is it in a datetime format or splitted?
      if(defined($columns{'DateTime'})) {
          # date - column 0 ('DateTime')
          $oWkC = $oWkS->{Cells}[$iR][$columns{'DateTime'}];
          ($date, $time) = ($oWkC->Value =~ /(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d)/);
      } else {
          # date - column 0 ('Date')
          $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
          next if( ! $oWkC );
          next if( ! $oWkC->Value );
          $date = ParseDate( $oWkC->Value );
          next if( ! $date );

          # time
          $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
          next if( ! $oWkC );
          $time = ParseTime($oWkC->Value) if( $oWkC->Value );
      }

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("KinoPolska: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # title
      next if(!defined($columns{'Title'}));
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = ucfirst(lc(norm($oWkC->Value))) if( $oWkC->Value );

      next if(!defined($title));

      # dont output errors if there is no title (End of program)
      if($title) {
        $title =~ s/\((\d\d\d\d)\)$//;
        $title = norm($title);
      }

      if($title and $title =~ /, (the|a|an|i|il)$/i) {
        my ($word2) = ($title =~ /, (the|a|an|i|il)$/i);
        $title =~ s/, (the|a|an|i|il)$//i;
        $title = norm(ucfirst(lc($word2)) . " ".$title);
      }

      next if(!defined($title));

      # # End of airtime
      if( ($title eq "End of program" or $title eq "Konec vysílání") )
      {
      	$title = "end-of-transmission";
      }

	  # extra info
	  my $year = $oWkS->{Cells}[$iR][$columns{'Year'}]->Value if defined($columns{'Year'}) and $oWkS->{Cells}[$iR][$columns{'Year'}];

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
      };

	  # Extra
	  $ce->{description}     = norm($oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value) if defined($columns{'Synopsis'}) and $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
	  $ce->{subtitle}        = ucfirst(lc(norm($oWkS->{Cells}[$iR][$columns{'Episode Title'}]->Value))) if defined($columns{'Episode Title'}) and $oWkS->{Cells}[$iR][$columns{'Episode Title'}];
	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Cast'}]->Value))          if defined($columns{'Cast'}) and $oWkS->{Cells}[$iR][$columns{'Cast'}];
	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Director'}]->Value))      if defined($columns{'Director'}) and $oWkS->{Cells}[$iR][$columns{'Director'}];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      # org title
      if(defined $columns{'ORGTitle'}) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'ORGTitle'}];
        my $title_org = $oWkC->Value if( $oWkC->Value );
        $ce->{original_title} = ucfirst(lc(norm($title_org))) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
        $ce->{original_title} =~ s/\((\d\d\d\d)\)$// if defined($ce->{original_title});
        $ce->{original_title} = norm($title) if defined($ce->{original_title});

        if(defined($ce->{original_title}) and $ce->{original_title} =~ /, (the|a|an|i|il)$/i) {
            my ($word) = ($ce->{original_title} =~ /, (the|a|an|i|il)$/i);
            $ce->{original_title} =~ s/, (the|a|an|i|il)$//i;
            $ce->{original_title} = norm(ucfirst(lc($word)) . " ".$ce->{original_title});
        }
      }

      # Movies
      if(defined($columns{'Director'}) and $oWkS->{Cells}[$iR][$columns{'Director'}]) {
        $ce->{program_type} = "movie";
      }

      # Episode?
      my ($ep, $dummy1, $dummy2);
      if($ce->{title} =~ /(, |)(cz.|odc\.) (\d+)/) {
        ($dummy1, $dummy2, $ep) = ($ce->{title} =~ /(, |)(cz.|odc\.) (\d+)/);
        $ce->{title} =~ s/(, |)(cz.|odc\.) (\d+) (A|B|C|SUB)//i;
        $ce->{title} =~ s/(, |)(cz.|odc\.) (\d+)//i;
        $ce->{title} = norm($ce->{title});

        $ce->{episode} = sprintf( ". %d .", $ep-1 );
        $ce->{program_type} = "series";
      }

      progress("KinoPolska: $chd->{xmltvid}: $time - $ce->{title}");

      $dsh->AddProgramme( $ce );


    }
  }

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
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\.\d+\.\d+$/ ) { # format '01.11.2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ ) { # format '01.11.2008'
    ( $year, $month, $day ) = ( $text =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

 # $text =~ s/ AM\/PM//g; # They fail sometimes
 # $text = ExcelFmt('hh:mm', $text);

  my( $hour , $min );

  if( $text =~ /^\d+:\d+/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /, /, $str );

  return join( ";", grep( /\S/, @persons ) );
}

1;

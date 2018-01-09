package NonameTV::Importer::Nonstop_XLS;

use strict;
use warnings;

=pod
Importer for Turner/NONSTOP

Channels: TNT Sweden, TNT Norway, TNT Denmark

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
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xlsm|xlsx)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Nonstop_XLS: Unknown file format: $file" );
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

  progress( "Nonstop_XLS: $chd->{xmltvid}: Processing $file" );
  if ( $file =~ /\.(xlsx|xlsm)$/i ){ $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    my $foundcolumns = 0;

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Nonstop_XLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    my $i = 0;
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
      			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series Title/i );
            $columns{'EpTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode\/program Title/i );
            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Day/i );
            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/i );
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/i );
            $columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season/i );
            $columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode/i );
            $columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description/i );
            $columns{'Production Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Production Year/i );
            $columns{'Actors'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Actors/i );
            $columns{'Directors'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Directors/i );


            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /(Day|Date)/i );
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

      # Batch
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			     # save last day if we have it in memory
		       #	FlushDayData( $channel_xmltvid, $dsh , @ces );
			     $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Nonstop_XLS: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	    # time
	    $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ExcelFmt('hh:mm', $time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      #next if( ! $oWkC );

      my $field2 = int2col($columns{'Title'}).$i;
      my $title = $ref->[1]{$field2};

      $title =~ s/&amp;/&/ if( $title );
      $title =~ s/- Season (\d+)(.*)//i if( $title );

      # Episode Title
      my $subtitle;
      if(defined($columns{'EpTitle'})) {
        my $field3 = int2col($columns{'EpTitle'}).$i;
        $subtitle = $ref->[1]{$field3};
      }

      if(!defined($title) and defined($subtitle)) {
        $title = $subtitle;
        $subtitle = undef;
      }

      next if( ! $title );

  	  # extra info
  	  my $desc = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if defined $columns{'Description'} and $oWkS->{Cells}[$iR][$columns{'Description'}];
  	  my $year = $oWkS->{Cells}[$iR][$columns{'Production Year'}]->Value if defined $columns{'Production Year'} and $oWkS->{Cells}[$iR][$columns{'Production Year'}];

      progress("Nonstop_XLS: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
      };

  	  # Extra
      $ce->{description}     = norm($desc) if defined($desc);
      $ce->{title}           =~ s/&amp;/&/g;
      $ce->{subtitle}        = $subtitle if defined($subtitle) and $subtitle ne $title;
      $ce->{subtitle}        =~ s/&amp;/&/g if defined($ce->{subtitle});
      $ce->{subtitle}        =~ s/Finale\: //i if defined($ce->{subtitle});
      $ce->{subtitle}        =~ s/Pilot\: //i if defined($ce->{subtitle});
  	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Actors'}]->Value))  if defined($columns{'Actors'}) and $oWkS->{Cells}[$iR][$columns{'Actors'}];
  	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Directors'}]->Value))  if defined($columns{'Directors'}) and $oWkS->{Cells}[$iR][$columns{'Directors'}];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      ## Episode
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}];
      my $episode = $oWkC->Value if( $oWkC );

      $oWkC = $oWkS->{Cells}[$iR][$columns{'Season'}];
      my $season = $oWkC->Value if( $oWkC );

      if(defined($episode) and $episode ne "" and $episode > 0) {
        $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";
      }

      if(defined($ce->{episode}) and defined($season) and norm($season) ne "" and $season > 0) {
        $ce->{episode} = $season-1 . $ce->{episode};
      }

      $ce->{subtitle} =~ s|\s*-\s+part\s+(\d+)$| ($1)|i if defined $ce->{subtitle};
      $ce->{subtitle} =~ s|(.*), The$|The $1| if defined $ce->{subtitle};
      $ce->{subtitle} =~ s|(.*), A$|A $1| if defined $ce->{subtitle};
      $ce->{subtitle} =~ s|(.*), An$|An $1| if defined $ce->{subtitle};

      # It's a movie
      if(not defined($ce->{episode}) and $title !~ /Teleshopping/i) {
        $ce->{program_type} = 'movie';
      } elsif(defined($ce->{subtitle}) and $ce->{subtitle} ne "") {
        $ce->{program_type} = "series";
      }

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

  if( $text =~ /^(\d\d\d\d)-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } elsif( $text =~ /^\d+-\d+-(\d\d\d\d)$/ ) { # format '2011-07-01'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  }elsif( $text =~ /^(\d|\d\d)-\d+-(\d\d)$/ ) { # format '9-2-15'
    ( $month, $day, $year ) = ( $text =~ /^(\d|\d\d)-(\d+)-(\d\d)$/ );
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

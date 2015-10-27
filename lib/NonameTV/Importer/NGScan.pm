package NonameTV::Importer::NGScan;

use strict;
use warnings;

=pod
Importer for Nat. Geo. Scandinavia

Channels: Nat. Geo. Norway, Sweden, Denmark, Finland

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

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "NGScan: Unknown file format: $file" );
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

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "NGScan: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

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

			      $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Series \(English\)$/ );
			      $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Series \(English\)$/ );

            $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(English\)/ );
            $columns{'Episode Title EN'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(English\)/ );

            $columns{'Ser No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series No/ );
            $columns{'Ep No'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode No/ );

            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(English\)/ );

            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ and $oWkS->{Cells}[$iR][$iC]->Value !~ /EET/ );
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/ and $oWkS->{Cells}[$iR][$iC]->Value !~ /EET/ ); # Dont set the time to EET

            $columns{'Premiere'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Premiere$/ );

            # Swedish
			      if($chd->{sched_lang} eq "sv") {
			         $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series \(Swedish\)/ );
			         $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(Swedish\)/ );
               $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(Swedish\)/ );
			      }

			      # Norwegian
            if($chd->{sched_lang} eq "no") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series \(Norwegian\)/ );
			          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(Norwegian\)/ );
                $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(Norwegian\)/ );
			      }

			      # Danish
            if($chd->{sched_lang} eq "da") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series \(Danish\)/ );
			          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(Danish\)/ );
                $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(Danish\)/ );
			      }

			      # Finnish
            if($chd->{sched_lang} eq "fi") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series \(Finnish\)/ );
			          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(Finnish\)/ );
                $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(Finnish\)/ );
			      }

            # Polish
            if($chd->{sched_lang} eq "pl") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series \(Polish\)/ );
			          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description \(Polish\)/ );
                $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode \(Polish\)/ );
			      }

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
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			# save last day if we have it in memory
			$dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("NGScan: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	    # time
	    $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = ParseTime($oWkC->Value) if( $oWkC->Value );

      # title
      my ($firsttitle, $eptitle);
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      $firsttitle = norm($oWkC->Value) if defined $oWkC;

      # eptitle
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode Title'}];
      $eptitle = norm($oWkC->Value);

      my $title = $firsttitle || $eptitle;

      next if( ! $title );

	    # episode and season
      my ($epino, $seano, $desc);
      $epino = $oWkS->{Cells}[$iR][$columns{'Ep No'}]->Value if defined $oWkS->{Cells}[$iR][$columns{'Ep No'}];
      $seano = $oWkS->{Cells}[$iR][$columns{'Ser No'}]->Value if defined $oWkS->{Cells}[$iR][$columns{'Ser No'}];

	    # extra info
  	  $desc = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if defined $oWkS->{Cells}[$iR][$columns{'Synopsis'}];

      progress("NGScan: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      # Extra
      if(defined($eptitle) and norm($eptitle) ne $ce->{title}) {
        $ce->{subtitle} = $eptitle;
      }

      # org title
      my $title_org;
      if(defined $columns{'ORGTitle'} and defined $oWkS->{Cells}[$iR][$columns{'ORGTitle'}]) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'ORGTitle'}];
        $title_org = $oWkC->Value if( $oWkC->Value );
        $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      } elsif(defined $eptitle and !defined $firsttitle and (defined $columns{'Episode Title EN'} and defined $oWkS->{Cells}[$iR][$columns{'Episode Title EN'}])) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode Title EN'}];
        $title_org = $oWkC->Value if( $oWkC->Value );
        $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      }

      # Premiere
      my $premiere = $oWkS->{Cells}[$iR][$columns{'Premiere'}]->Value if $oWkS->{Cells}[$iR][$columns{'Premiere'}];
      if( defined($premiere) and $premiere eq "Y" )
      {
        $ce->{new} = "1";
      }
      else
      {
        $ce->{new} = "0";
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

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text2 ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min );

  if( $text2 =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text2 =~ /^(\d+):(\d+)$/ );
  }

  if($hour >= 24) {
  	$hour = $hour-24;

  	#print("Hour: $hour\n");
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

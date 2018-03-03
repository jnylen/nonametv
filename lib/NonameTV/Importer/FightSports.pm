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
use Data::Dumper;

use NonameTV qw/norm ParseExcel formattedCell AddCategory MonthNumber/;
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

  if( $file =~ /\.(xls|xlsx)$/i ){
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

  # Process
  progress( "FightSports: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "FightSports: $file: Failed to parse excel" );
    return;
  }

  # process
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "FightSports: $chd->{xmltvid}: Processing worksheet: $oWkS->{label}" );

    my %columns = ();
    my $foundcolumns = 0;
    my $currdate = "x";

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Calendar Date/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Calendar Time/i );
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program Listing Title/i );
            $columns{'Ep Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program Episode Title/i );
            $columns{'Ses No'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Season/i );
            $columns{'Ep No'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Episode Number/i );
            $columns{'Genre'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program Category/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program Synopsis/i );


            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^Calendar Date/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # date - column 1
      my $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );

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
      my $time = ParseTime(formattedCell($oWkS, $columns{'Time'}, $iR));

      # duration - column 3

      # title - column 4
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);

      # episode title - column 5
      my $eptitle = formattedCell($oWkS, $columns{'Ep Title'}, $iR);

      # season - column 6
      my $season = formattedCell($oWkS, $columns{'Ses No'}, $iR);

      # episode - column 7
      my $episode = formattedCell($oWkS, $columns{'Ep No'}, $iR);

      # category - column 8
      my $cate = formattedCell($oWkS, $columns{'Genre'}, $iR);

      # description - column 10
      my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);

      my $ce = {
        channel_id  => $chd->{channel_id},
        start_time  => $time,
        title       => norm($title),
        description => norm($desc)
      };

      # Extra info
      $ce->{subtitle} = norm($eptitle) if defined $eptitle;

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

  #$text =~ s/^\s+//;

  #print("text: $text\n");

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } elsif( $text =~ /^(\d+)-([[:alpha:]]+)-(\d+)$/ ){ # format '11-Jan-2018'
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-([[:alpha:]]+)-(\d+)$/ );
    $month = MonthNumber($monthname, "en");
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min, $secs, $ampm );

  if( $text =~ /^\d+:\d+ (am|pm)/i ){
    ( $hour , $min, $ampm ) = ( $text =~ /^(\d+):(\d+) (AM|PM)/ );
    $hour = ($hour % 12) + (($ampm eq 'AM') ? 0 : 12);
  } elsif($text =~ /^\d+:\d+$/i) {
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  } else {
    print Dumper($text);
  }

  if($hour >= 24) {
    $hour -= 24;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

package NonameTV::Importer::YFE;

use strict;
use warnings;

=pod

Import data from YFE

Channels: FIX&FOXI and RiC

=cut

use utf8;

use DateTime;
use Data::Dumper;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use NonameTV qw/norm AddCategory AddCountry CleanSubtitle/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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
    error( "BBCWW: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "$chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  my($iR, $oWkS, $oWkC);
  my %columns = ();
  my $currdate = "x";

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    my $foundcolumns = 0;

    # start from row 0
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Find columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Title/i );
            $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^OT$/i );
            $columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Start/i );
            $columns{'Stop'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Stop/i );

            $columns{'EpTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /EpisodeTitle/i );

            $columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Season/i );
            $columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /EpisodeNumber/i );
            $columns{'Genre'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Genre/i );
            $columns{'EpSynopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /EpisodeText/i );
            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /GeneralPlotOutline/i );

            $columns{'ProdCountry'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Country of Production/i );
            $columns{'ProdYear'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Year of production/i );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # start - column 0 ('Start')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $start = parseTimestamp( $oWkC->Value );
      my $date = $start->ymd("-");

      # stop - column 1 ('Stop')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Stop'}];
      my $stop = parseTimestamp( $oWkC->Value );

      # title - column 2 ('Title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = norm($oWkC->Value);

      # description
      $oWkC = $oWkS->{Cells}[$iR][$columns{'EpSynopsis'}];
      my $epdesc = norm($oWkC->Value);
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
      my $generaldesc = norm($oWkC->Value);

      # YFE CHANNELS ARE VG LICENSED
      my $desc = ($epdesc || $generaldesc);

      # Start date
      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
			    $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("$chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $start->hms(":"),
      };

      # episode
      my $epino = $oWkS->{Cells}[$iR][$columns{'Episode'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode'}];
      my $seano = $oWkS->{Cells}[$iR][$columns{'Season'}]->Value if defined($columns{'Season'}) and $oWkS->{Cells}[$iR][$columns{'Season'}];
      my $year = $oWkS->{Cells}[$iR][$columns{'ProdYear'}]->Value if $oWkS->{Cells}[$iR][$columns{'ProdYear'}];
      my $genre = $oWkS->{Cells}[$iR][$columns{'Genre'}]->Value if $oWkS->{Cells}[$iR][$columns{'Genre'}];
      my $countrie = $oWkS->{Cells}[$iR][$columns{'ProdCountry'}]->Value if $oWkS->{Cells}[$iR][$columns{'ProdCountry'}];
      $ce->{subtitle} = CleanSubtitle(norm($oWkS->{Cells}[$iR][$columns{'EpTitle'}]->Value)) if $oWkS->{Cells}[$iR][$columns{'EpTitle'}];

      # Org Title
      $ce->{original_title} = CleanSubtitle(norm($oWkS->{Cells}[$iR][$columns{'ORGTitle'}]->Value)) if defined($columns{'ORGTitle'}) and $oWkS->{Cells}[$iR][$columns{'ORGTitle'}];

      # year
      if(defined($year) and $year =~ /\((\d\d\d\d)\)/) {
        $ce->{production_date} = "$1-01-01";
      }

      # Episode
      if( $epino ){
        $epino =~ s/[a-z]//;
        if(defined $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      # Genre
      my @genres;
      foreach my $g (split(", ", $genre)) {
        my ( $program_type, $category ) = $self->{datastore}->LookupCat( "YFE_genre", $g );
        push @genres, $category if defined $category;
      }

      if( scalar( @genres ) > 0 ) {
        $ce->{category} = join "/", @genres;
      }

      # countries
      my @countries;
      foreach my $con (split(", ", $countrie)) {
          my ( $c ) = $self->{datastore}->LookupCountry( "YFE", $con );
          push @countries, $c if defined $c;
      }

      if( scalar( @countries ) > 0 ) {
            $ce->{country} = join "/", @countries;
      }



      $dsh->AddProgramme( $ce );

      progress("$start - $title");

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub parseTimestamp {
  my ($timestamp) = @_;

  if( $timestamp ){
    # 13-06-2016 06:00:00
    my ($day, $month, $year, $hour, $minute, $second) = ($timestamp =~ m/^(\d{2})-(\d{2})-(\d{4}) (\d{2}):(\d{2}):(\d{2})$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => 'Europe/Berlin'
    );
    $dt->set_time_zone( 'UTC' );
    return( $dt );
  } else {
    return undef;
  }
}

1;

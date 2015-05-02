package NonameTV::Importer::XITE;

use strict;
use warnings;


=pod

Import data from XLS files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::Read;
use Time::Piece;

use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm normUtf8 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  }

  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "XITE: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $year;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week) = ($file =~ /EPG_(\d\d)/);

  if(!defined $year) {
    my $t = Time::Piece->new();
    $year = $t->year;
  } else { $year += 2000; }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;
  $dsh->StartBatch( $batchid , $chd->{id} );

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    progress( "XITE: Processing worksheet: $oWkS->{Name}" );

    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # Current day
      if( $date ne $currdate ){
        progress("XITE: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # start
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $start = $oWkC->Value if( $oWkC->Value );

      # title
      $oWkC = $oWkS->{Cells}[$iR][4];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # desc
      $oWkC = $oWkS->{Cells}[$iR][5];
      next if( ! $oWkC );
      my $desc = $oWkC->Value if( $oWkC->Value );

      my $ce = {
        channel_id => $channel_id,
        start_time => $start,
        title => norm($title),
        description => norm($desc),
      };

	  progress("XITE: $start - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

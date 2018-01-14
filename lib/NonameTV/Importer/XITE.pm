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

      # start
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $start = $self->parseTimestamp($oWkC->Value) if( $oWkC->Value );

      # title
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # desc
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $desc = $oWkC->Value if( $oWkC->Value );

      my $ce = {
        channel_id => $channel_id,
        start_time => $start,
        title => norm($title),
        description => norm($desc),
      };

	    progress("XITE: $start - $title") if $title;
      $ds->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})([+-]\d{2}:\d{2}|)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    if( $offset ){
      $offset =~ s|:||;
    } else {
      $offset = 'Europe/Berlin';
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => $offset
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

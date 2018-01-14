package NonameTV::Importer::GlobalListings_Tab;

use strict;
use warnings;

=pod

Import data from Viasat's press-site. The data is downloaded in
tab-separated text-files.

Features:

Proper episode and season fields. The episode-field contains a
number that is relative to the start of the series, not to the
start of this season.

program_type

=cut


use DateTime;
use Encode;
use File::Slurp;

use NonameTV qw/AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub ImportContentFile {
  my $self = shift;

  my( $filename, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  my $currdate = "x";
  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};

  # Decode the string into perl's internal format.
  # see perldoc Encode
  my $cref=`cat \"$filename\"`;

  #my $str = decode( "utf-8", $$cref );

  my @rows = split("\n", $cref );

  if( scalar( @rows < 2 ) )
  {
    error( "$filename: No data found" );
    return 0;
  }

  for ( my $i = 0; $i < scalar @rows; $i++ )
  {
    my $inrow = $self->row_to_hash($filename, $rows[$i] );
    my $date = ParseDate($inrow->[1]);

    if( $date ) {
      if( $date ne $currdate ) {
        if( $currdate ne "x" ){
          # save last day if we have it in memory
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("GlobalListings_Tab: $xmltvid: Date is $date");
      }
    }

    my $start = $inrow->[2];

    # Maybe we should put original title in a column sometime?
		my $title = $inrow->[4];

    my $description = $inrow->[9];

    $description = norm( $description );

    my $ce = {
      title => norm($title),
      description => $description,
      start_time => $start,
    };


    progress("GlobalListings_Tab: $chd->{xmltvid}: $start - $title");
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub row_to_hash
{
  my $self = shift;
  my( $filename, $row ) = @_;

  my @coldata = split( "\t", $row );
  my %res;

  return \@coldata;
}

sub ParseDate {
  my( $text ) = @_;

  my( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

package NonameTV::Importer::HopeChannel;

use strict;
use warnings;

=pod

Import data for HopeChannel

Features:

=cut

use utf8;

use DateTime;
use Data::Dumper;
use XML::LibXML;
use IO::Scalar;
use Archive::Zip qw/:ERROR_CODES/;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }

  return;
}


sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HopeChannel: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//broadcasts/broadcast" );

  if( $rows->size() == 0 ) {
    error( "DreiPlus: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  my $date = $doc->findvalue('.//broadcasts/date');

  my $batchid = $chd->{xmltvid} . "_" . $date;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  foreach my $row ($rows->get_nodelist) {
    my $starttime = $row->findvalue( 'time' );

    # Date
    if($date ne $currdate ) {
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("HopeChannel: Date is: $date");
    }

    # Titles
    my $stitle = $row->findvalue( 'series' );
    my $subtitle = $row->findvalue( 'untertitel' );

    # Desc
    my $desc = $row->findvalue( 'shortpresstext' );

    my $ce = {
      channel_id => $chd->{id},
      title => norm($stitle),
      start_time => $date . " " . $starttime,
    };

#


    # Subtite
    if($subtitle ne "") {
      $ce->{subtitle} = norm($subtitle);
    }

    # Add programme
    $ds->AddProgrammeRaw( $ce );
    progress( "HopeChannel: $chd->{xmltvid}: $ce->{start_time} - $stitle" );
  } # next row

  $dsh->EndBatch( 1 );

  return 1;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

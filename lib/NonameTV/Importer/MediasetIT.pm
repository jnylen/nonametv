package NonameTV::Importer::MediasetIT;

use strict;
use warnings;

=pod

Imports data for Mediaset channels

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/ParseXmlFile norm AddCategory AddCountry MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Rome" );
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
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "MediasetIT: $chd->{xmltvid}: Processing XML $file" );

  my $doc = ParseXmlFile($file);

  # Find all paragraphs.
  my $ns = $doc->find( "//Record" );

  if( $ns->size() == 0 ) {
    error "No Programs found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
      my $date  = ParseDate($progs->findvalue( 'Data' ));

      # Date
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "07:00" );
        $currdate = $date;

        progress("MediasetIT: Date is: $date");
      }

      my $title_prod = norm($progs->findvalue( 'TitoloProd' ));
      my $title_full = norm($progs->findvalue( 'Titolo' ));
      my $title = $title_prod || $title_full;
      my $time  = $progs->findvalue( 'Ora' );

      my $type  = $progs->findvalue( 'Tipo' );

      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $time,
      };

      # Genre
      if( $type ){
          my($program_type, $category ) = $ds->LookupCat( 'MediasetIT', $type );
          AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

      progress( "MediasetIT: $chd->{xmltvid}: $time - $title" );
  }

  $dsh->EndBatch( 1 );

  return 1;
}


sub ParseDate {
  my( $text ) = @_;
  my( $dayname, $day, $monthname, $year );
  my $month;

  if( ( $day, $month, $year ) = ( $text =~ /^(\d+)\-(\d+)\-(\d\d\d\d)$/ ) ) { # format '07.09.2017'
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

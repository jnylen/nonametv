package NonameTV::Importer::ERR;

use strict;
use warnings;

=pod

Imports data for ETV, ETV2, ETV+

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/ParseXml norm normLatin1 normUtf8 AddCategory AddCountry MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Tallinn" );
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

  progress( "ERR: $chd->{xmltvid}: Processing XML $file" );

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;
  
  $cref =~ s| encoding="UTF-8"| encoding="windows-1257"|;
  $cref =~ s| & | &amp; |g;

  my $xml = XML::LibXML->new;
  $xml->load_ext_dtd(0);
  my $doc = $xml->parse_string($cref);

  # Find all paragraphs.
  my $ns = $doc->find( "//PROGRAM" );

  if( $ns->size() == 0 ) {
    error "No Programs found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
    my $date  = ParseDate($progs->findvalue( 'DATE' ));

    # Date
    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
        $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("ERR: Date is: $date");
    }

    my $title = $progs->findvalue( 'TITLE' );
    my $title_org = $progs->findvalue( 'ORIGTITLE' );
    my $subtitle = $progs->findvalue( 'SUBTITLE' );
    my $title_short = $progs->findvalue( 'TITLE_SHORT' );
    my $desc  = $progs->findvalue( 'DESCRIPTION' );
    my $time  = $progs->findvalue( 'TIME_FROM' );

    #print("org: $title\n");
    # Remove shit from the title
    if($subtitle ne "") {
      $title =~ s/$subtitle//g;
    }

    # Remove org title
    if($title_org ne "") {
      $title =~ s/$title_org//g;
      $title =~ s/\(, /\(/g;
    }

    # Remove short title
    my ( $realtitle, $st );
    if($title_short ne "") {
      $title_short =~ s/\*//g;
      $title =~ s/$title_short//g;

      # Sometimes episode title is in the title remove it
      if($title_short =~ /\:/) {
        ( $realtitle, $st ) = ($title_short =~ /(.*)\: (.*)/);

        #print("realtitle: $realtitle\n");
        $title =~ s/$realtitle//g;
      }
      
      $title = norm($title);
      $title =~ s/^, //;
      $title =~ s/^\?, //;
      $title = norm($title);
      $title =~ s/\*//g;
    }

    # Programme
    my $ce = {
      title       	 => norm($title_short),
      description    => norm($desc),
      start_time  	 => $time,
    };

    if(defined($subtitle)) {
      my ($program_type, $category ) = $ds->LookupCat( "ERR", $subtitle );
      AddCategory( $ce, $program_type, $category );
  	}

    # Country and prodyear
    if($title =~ /\((.*?) (\d\d\d\d)\)$/i) {
      $title =~ s/\((.*?)\)$//;
      $title = norm($title);
      my @arraycountries;

      foreach my $country (split("/", $1)) {
        my($country2 ) = $ds->LookupCountry( "ERR", norm($country) );
        #AddCountry( $ce, $country2 );
      }

      $ce->{production_date} = $2."-01-01" if defined($2) and $2 ne "" and $2 ne "0000";
    }

    # Parse episode
    if($title =~ /^(\d+), (\d+)\/(\d+)\: (.*?)$/) {
      $ce->{episode} = sprintf( "%d . %d/%d .", $1-1, $2-1, $3 );
      
      # Set real subtitle / title
      if(norm($st) eq norm($4)) {
        $ce->{subtitle} = norm($4);
        $ce->{title} = norm($realtitle);
      }
    } elsif($title =~ /^(\d+)\/(\d+)\: (.*?)$/) {
      $ce->{episode} = sprintf( ". %d/%d .", $1-1, $2 );
      
      # Set real subtitle / title
      if(norm($st) eq norm($3)) {
        $ce->{subtitle} = norm($3);
        $ce->{title} = norm($realtitle);
      }
    } elsif($title =~ /^(\d+), (\d+)\/(\d+)$/) {
      $ce->{episode} = sprintf( "%d . %d/%d .", $1-1, $2-1, $3 );
    } elsif($title =~ /^(\d+)\/(\d+)$/) {
      $ce->{episode} = sprintf( ". %d/%d .", $1-1, $2 );
    } elsif($title =~ /^(\d+)$/) {
      $ce->{episode} = sprintf( ". %d .", $1-1 );
    }

    # ORG Title
    if($title_org ne "")  {
      $ce->{original_title} = norm($title_org);
    }
    
    #print("new: $title\n");
    progress( "ERR: $chd->{xmltvid}: $time - " . $ce->{title} );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}


sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+\.\d+\.\d\d\d\d$/ ) { # format '07.09.2017'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d\d\d\d)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

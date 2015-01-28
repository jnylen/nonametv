package NonameTV::Importer::DMAX;

use strict;
use warnings;

=pod

Import data for Discovery Channel Germany.
Channels: DMAX, AP, Discovery, TLC

Features:

=cut

use utf8;

use DateTime;
use Data::Dumper;
use XML::LibXML;
use IO::Scalar;
use Archive::Zip qw/:ERROR_CODES/;
use File::Basename;

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

  $self->{datastore}->{augment} = 1;

  $self->{KeepDesc} = 0;
  if (!defined $self->{HaveVGMediaLicense}) {
    warn( 'Extended event information (texts, pictures, audio and video sequences) is subject to a license sold by VG Media. Set HaveVGMediaLicense to yes or no.' );
    $self->{HaveVGMediaLicense} = 'no';
  }
  if ($self->{HaveVGMediaLicense} eq 'yes') {
    $self->{KeepDesc} = 1;
  }

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;
  my $tag = $chd->{grabber_info};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.zip$/i ) {
  	# When ParseExcel can load a XLS file
  	# from a string Please remove this
  	# as this is too stupid.

    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @members = $zip->members();
    foreach my $member (@members) {
      # There can be multiple schedules in one.
      if(basename($member->{fileName}) =~ /^$tag/ and basename($member->{fileName}) =~ /\.xml$/i) {
        d "Using file $member->{fileName}";

        # file exists - could be a new file with the same filename
        # remove it.
        my $filename = '/tmp/'.basename($member->{fileName});
        if (-e $filename) {
            unlink $filename; # remove file
        }

        my $content = $zip->contents( $member->{fileName} );

        open (MYFILE, '>>'.$filename);
        print MYFILE $content;
        close (MYFILE);

        $self->ImportXML( $filename, $chd );
        unlink $filename; # remove file
      }
    }

  } else {
    error( "DMAX: Unknown file format: $file" );
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

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns='http://pid.rzp.hbv.de/xml/'||;
  $cref =~ s| xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'||;

  $cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;


  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if( not defined( $doc ) ) {
    error( "DMAX: $file: Failed to parse xml" );
    return;
  }


  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( s => 'http://pid.rzp.hbv.de/xml/' );

  my $rows = $xpc->findnodes( '//s:sendung', $doc );

  if( $rows->size() == 0 ) {
    error( "DMAX: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  sub by_start {
    return $xpc->findvalue('s:termin/@start', $a) cmp $xpc->findvalue('s:termin/@start', $b);
  }

  foreach my $program (sort by_start $rows->get_nodelist) {
    $xpc->setContextNode( $program );
    my $start = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
    my $end = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) );

    my $ce = ();
    $ce->{channel_id} = $chd->{id};

    $ce->{start_time} = $start->ymd("-") . " " . $start->hms(":");
    $ce->{end_time} = $end->ymd("-") . " " . $end->hms(":");

    if($start->ymd("-") ne $currdate ) {
		if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $start->ymd("-");
		$dsh->StartBatch( $batchid , $chd->{id} );

        $dsh->StartDate( $start->ymd("-") , "06:00" );
        $currdate = $start->ymd("-");
        progress("DMAX: $chd->{xmltvid}: Date is: ".$start->ymd("-"));
    }

        $ce->{title} = norm($xpc->findvalue( 's:titel/@termintitel' ));

        my $title_org;
        $title_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' );
        $ce->{original_title} = norm($title_org) if $title_org and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

        my ($folge, $staffel);
        my $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="untertitel"]/@aliastitel' );
        my $subtitle_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaluntertitel"]/@aliastitel' );
        if( $subtitle ){
          if( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \((\d+)\. Staffel\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \(Staffel (\d+)\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          } else {
            # unify style of two or more episodes in one programme
            $subtitle =~ s|\s*/\s*| / |g;
            # unify style of story arc
            $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
            $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
            $ce->{subtitle} = norm( $subtitle );
          }
        }

        if( $subtitle_org ){
          if( ( $folge, $staffel ) = ($subtitle_org =~ m|^Folge (\d+) \(Staffel (\d+)\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $staffel, $folge ) = ($subtitle_org =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge ) = ($subtitle_org =~ m|^Folge (\d+)$| ) ){
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          } else {
            # unify style of two or more episodes in one programme
            $subtitle_org =~ s|\s*/\s*| / |g;
            # unify style of story arc
            $subtitle_org =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
            $subtitle_org =~ s|[ ,-]+Part (\d)+$| \($1\)|;
            $ce->{original_subtitle} = norm( $subtitle_org ) if defined $ce->{subtitle} and $ce->{subtitle} ne norm( $subtitle_org );
            $ce->{subtitle} = norm( $subtitle_org ) if not defined $ce->{subtitle};
          }
        }

        my $production_year = $xpc->findvalue( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionszeitraum/s:jahr/@von' );
        if( $production_year =~ m|^\d{4}$| ){
          $ce->{production_date} = $production_year . '-01-01';
        }

        my @countries;
        my $ns4 = $xpc->find( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionsland/@laendername' );
        foreach my $con ($ns4->get_nodelist)
	    {
	        my ( $c ) = $self->{datastore}->LookupCountry( "KFZ", $con->to_literal );
	  	    push @countries, $c if defined $c;
	    }

        if( scalar( @countries ) > 0 )
        {
              $ce->{country} = join "/", @countries;
        }

        my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
        if( $genre ){
          my ( $program_type2, $category2 ) = $self->{datastore}->LookupCat( "DMAX", $genre );
          AddCategory( $ce, $program_type2, $category2 );
        }

        #Descr
        my $desc = $xpc->findvalue( 's:text[@textart="Kurztext"]' );
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Beschreibung"]' );
        }
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Allgemein"]' );
        }

        $ce->{description} = norm($desc) if $self->{KeepDesc} and $desc and $desc ne "";

        $ds->AddProgrammeRaw( $ce );

        progress("DMAX: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});

  } # next row

  $dsh->EndBatch( 1 );

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{2}:\d{2}|)$/);
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

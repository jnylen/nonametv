package NonameTV::Importer::Tivo;

use strict;
use warnings;

=pod

Import data that is provided by Tivo for channels.

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;

use XML::LibXML;
use IO::Scalar;
use TryCatch;

use NonameTV qw/norm AddCategory/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

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

    my @files;

    my @members = $zip->members();
    foreach my $member (@members) {
      push( @files, $member->{fileName} ) if $member->{fileName} =~ /\.xml$/i;
    }

    my $numfiles = scalar( @files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $files[0]";

    # file exists - could be a new file with the same filename
    # remove it.
    my $filename = '/tmp/'.$files[0];
    if (-e $filename) {
    	unlink $filename; # remove file
    }

    my $content = $zip->contents( $files[0] );

    open (MYFILE, '>>'.$filename);
  	print MYFILE $content;
  	close (MYFILE);

    $self->ImportXML( $filename, $chd );
    unlink $filename; # remove file
  } else {
    error( "Tivo: Unknown file format: $file" );
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

  progress( "Tivo: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Tivo: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//listing" );

  if( $rows->size() == 0 ) {
    error( "Tivo: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  my $timezone = $doc->findvalue( '//channel/@timeZone' );

  foreach my $row ($rows->get_nodelist) {
    my $title   = $row->findvalue( './/title' );
    my $serdesc = $row->findvalue( './/synopsis' );
    my $epdesc  = $row->findvalue( './/episodeSynopsis' );
    my $desc    = $epdesc || $serdesc;

    $title =~ s|(.*), the$|The $1|i;
    $title =~ s|(.*), a$|A $1|i;
    $title =~ s|(.*),the$|The $1|i;


    my ($start);
    try {
      $start = $self->create_dt( $row->findvalue( './/broadcastDate' ), $timezone );
    }
    catch ($err) { print("error: $err"); next; }

    my $date = $start->ymd("-");

    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
           $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("Tivo: Date is: $date");
    }

    my $ce = {
      channel_id => $chd->{id},
      title => norm($title),
      start_time => $start->hms(":"),
      description => norm($desc),
    };

    # Extra
    my $programtype = $row->findvalue( './/programType' );
    my $genre       = $row->findvalue( './/genres' );
    my $prodyear    = $row->findvalue( './/yearOfProduction' );
    my $audio       = $row->findvalue( './/audioType' );
    my $sixteenNine = $row->findvalue( './/sixteenNine' );
    my $hd          = $row->findvalue( './/HD' );
    my @directors   = split(", ", $row->findvalue( './/directors' ));
    my @actors      = split(", ", $row->findvalue( './/actors' ));

    # Subtitle
    $ce->{subtitle} = norm($row->findvalue( './/episodeTitle' )) if defined $row->findvalue( './/episodeTitle' ) and $row->findvalue( './/episodeTitle' ) ne "";
    $ce->{subtitle} =~ s|(.*), the$|The $1|i if defined $ce->{subtitle};
    $ce->{subtitle} =~ s|(.*), a$|A $1|i if defined $ce->{subtitle};
    $ce->{subtitle} =~ s|(.*),the$|The $1|i if defined $ce->{subtitle};

    my ($season, $episode2, $newsub);
    if(defined($ce->{subtitle})) {
      if( ( $season, $episode2, $newsub ) = ($ce->{subtitle} =~ m|^S.son (\d+) - Episode (\d+)\: (.*?)$| ) ){
        $ce->{episode} = ($season - 1) . ' . ' . ($episode2 - 1) . ' .';
        $ce->{subtitle} = norm($newsub);
      }
    }


    # Episodenum
    my $episode      = $row->findvalue( './/episodeNb' );
    my $of_episode   = $row->findvalue( './/episodeCount' );
    if(!defined($ce->{episode}) and ($episode ne "") and ( $of_episode ne "") )
    {
      $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
    }

    # Program type
    my( $pty, $cat );
    if(defined($programtype) and $programtype and $programtype ne "") {
        ( $pty, $cat ) = $ds->LookupCat( 'Tivo_type', $programtype );
        AddCategory( $ce, $pty, $cat );
    }

    if(defined($genre) and $genre and $genre ne "") {
      my @genres = split(",", $genre);
      my @cats;
      foreach my $node ( @genres ) {
        my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tivo_genres", $node );
        push @cats, $categ if defined $categ;
      }
      $cat = join "/", @cats;
      AddCategory( $ce, $pty, $cat );
    }

    $ce->{stereo} = "mono" if $audio eq "mono";
    $ce->{aspect} = "16:9" if $sixteenNine eq "true";
    $ce->{aspect} = "4:3"  if $sixteenNine eq "false" or $sixteenNine eq "";
    $ce->{production_date} = "$prodyear-01-01" if(defined($prodyear) and $prodyear ne "");
    $ce->{actors} = join(";", @actors) if(@actors and scalar( @actors ) > 0 );
    $ce->{directors} = join(";", @directors) if(@directors and scalar( @directors ) > 0 );
    $ce->{quality} = "HDTV" if $hd eq "true";

    progress( "Tivo: $chd->{xmltvid}: $start - $title" );
    $dsh->AddProgramme( $ce );

  } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
  my $self = shift;
  my ($timestamp, $timezone) = @_;

  if( $timestamp ){
    my ($year, $month, $day, $hour, $minute) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/);
    if( !defined( $year )|| !defined( $hour ) || ($month < 1) ){
      w( "could not parse timestamp: $timestamp" );
      return undef;
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => $timezone
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

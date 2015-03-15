package NonameTV::Importer::TVAnytime;

use strict;
use warnings;

=pod

Import data from Xml-files in TV Anytime format.

Features:

=cut

use utf8;

use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Duration;
use XML::LibXML;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use Data::Dumper;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  # Silence
  $self->{SILENCE_DUPLICATE_SKIP} = 1;

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $filename, $chd ) = @_;
  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  my $currdate = "x";

  my $cref=`cat \"$filename\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns="urn:tva:metadata:2004"||;

  # XML
  my $parser = XML::LibXML->new;
  my $doc;
  eval { $doc = $parser->parse_string($cref); };

  if (not defined ($doc)) {
    f ("$filename: Failed to parse.");
    return 0;
  }

  # XPC
  my $xpc = XML::LibXML::XPathContext->new($doc);

  # Programinformation
  my %programs;
  foreach my $node ($xpc->findnodes("//ProgramInformation")) {
    my $prog = {};
    $prog->{ "id" } = $node->getAttribute('programId');
    $prog->{ "title" } = $xpc->findvalue(".//Title[attribute::type='main']", $node);
    $prog->{ "subtitle" } = $xpc->findvalue(".//Title[attribute::type='EpisodeTitle']", $node);
    $prog->{ "synopsis" } = $xpc->findvalue(".//Synopsis[attribute::length='short']", $node);
    $prog->{ "year" } = $xpc->findvalue(".//ReleaseInformation/ReleaseDate/Year", $node);

    # Grab subtitle from the title
    my( $t, $st ) = ($prog->{ "title" } =~ /(.*)\: (.*)/);
    if( defined( $st ) )
    {
        # This program is part of a series and it has a colon in the title.
        # Assume that the colon separates the title from the subtitle.
        $prog->{ "title" } = $t;
        $prog->{ "subtitle" } = $st;
    }

    if(my($season, $episode, $failure, $of_episodes) = ($prog->{ "synopsis" } =~ /\(S(\d+),\s+Ep\s+(\d+)\/(| )(\d+)\)/i)) {
        $prog->{ "xmltv_episode" } = sprintf( "%d . %d/%d .", $season-1, $episode-1, $of_episodes );
        $prog->{ "synopsis" } =~ s/\(S(\d+),\s+Ep\s+(\d+)\/(| )(\d+)\)//i;
    } else {
        $prog->{ "xmltv_episode" } = "";
    }

    $programs{ $prog->{ "id"  } } = $prog;
  }

  # Batch
  my ($year, $month, $day) = ($filename =~ /(\d\d\d\d)(\d\d)(\d\d)/);
  my $batchid = $chd->{xmltvid} . "_" . $year . "-" . $month . "-" . $day;
  $dsh->StartBatch( $batchid , $chd->{id} );


  # Programmes
  my $ns = $doc->findnodes( '//ScheduleEvent', $doc );
  if( $ns->size() == 0 ) {
    f ("$filename: No data found");
    return 0;
  }

  foreach my $p ($ns->get_nodelist) {
    $xpc->setContextNode( $p );
    my $start       = DateTime::Format::ISO8601->parse_datetime( $xpc->findvalue( 'PublishedStartTime' ) );
    my $stop        = ($start + DateTime::Format::Duration->new(pattern => 'PT%HH%MM%SS')->parse_duration($xpc->findvalue( 'PublishedDuration' )));
    my $program_id  = norm($xpc->findvalue( './Program/@crid' ));
    my $program     = $programs{$program_id};

    my $date = $start->ymd("-");
    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
      }

	  $currdate = $date;
	  $dsh->StartDate( $date , "06:00" );
      progress("TVAnytime: Date is: $date");
    }

    my $ce =
    {
      channel_id  => $chd->{id},
      title       => norm($program->{"title"}),
      start_time  => $start->hms(":"),
      end_time    => $stop->hms(":"),
      description => norm($program->{"synopsis"}),
    };

    $ce->{subtitle} = norm($program->{"subtitle"}) if $program->{"subtitle"} ne "" and $program->{"title"} ne $program->{"title"};

    # Prod. Year
    if( $program->{"year"} =~ m|^\d{4}$| ){
        $ce->{production_date} = $program->{"year"} . '-01-01';
    }

    $ce->{episode} = $program->{"xmltv_episode"} if $program->{"xmltv_episode"} ne "";
    $ce->{program_type} = "series" if $program->{"xmltv_episode"} ne "";

    progress("TVAnytime: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});
    $dsh->AddProgramme( $ce );

  }

  $dsh->EndBatch( 1 );

  return 1;
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

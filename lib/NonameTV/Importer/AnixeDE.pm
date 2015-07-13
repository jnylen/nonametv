package NonameTV::Importer::AnixeDE;

use strict;
use warnings;
use Encode qw/from_to/;

=pod

Sample importer for http-based sources.
See xxx for instructions.

=cut

use NonameTV::Log qw/f/;
use NonameTV qw/norm ParseXml/;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $date) = ( $objectname =~ /^(.+)_(.*)$/ );

  my $url = 'http://www.anixehd.tv/ait/anixesd/day_programm.php?wann=' . $date;

  # Only one url to look at and no error
  return ([$url], undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $doc = ParseXml ($cref);

  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $programs = $doc->find ('//CLIP');
  if( $programs->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  foreach my $program ($programs->get_nodelist) {
    my ($year, $month, $day, $hour, $minute, $second) = ($program->findvalue ('DATE') =~ m|^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$|);
    my $start_time = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => 'Europe/Berlin'
    );
    $start_time->set_time_zone ('UTC');

    my $title = $program->findvalue ('TITEL');
    my $description = $program->findvalue ('INFO');
    my $image = $program->findvalue ('BILD');

    my $ce = {
      channel_id => $chd->{id},
      start_time => $start_time->ymd ('-') . " " . $start_time->hms (':'),
      title => norm($title),
    };

    # Desc
    if ($description) {
      $ce->{description} = norm($description);
    }

    $ce->{fanart} = $image if defined($image) and $image ne "";
    $ce->{quality} = 'HDTV';
    $ce->{program_type} = 'series';


    my( $t, $st ) = ($ce->{title} =~ /(.*) - (.*)/);
    if( defined( $st ) )
    {
      my ( $folge );

      # This program is part of a series and it has a colon in the title.
      # Assume that the colon separates the title from the subtitle.
      $ce->{title} = $t;
      if( ( $folge ) = ($st =~ m|^Folge (\d+)$| ) ){
        $ce->{episode} = '. ' . ($folge - 1) . ' .';
      } elsif( ( $folge ) = ($st =~ m|^Episode (\d+)$| ) ){
        $ce->{episode} = '. ' . ($folge - 1) . ' .';
      } else {
        $ce->{subtitle} = norm($st);
      }
    }

    $self->{datastore}->AddProgramme ($ce);
  }

  return 1;
}


1;

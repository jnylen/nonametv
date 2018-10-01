package NonameTV::Importer::RTL2HTML;

use strict;
use warnings;

=pod

Importer för RTL2.de HTML.

=cut

use HTML::Entities;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Unicode::String;
use Data::Dumper;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f progress error/;

use NonameTV qw/Html2Xml norm/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Berlin" );
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;
    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );


  # Day=0 today, Day=1 tomorrow etc. Yesterday = yesterday

  my $dt = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day
                          );

  my $url = "http://www.rtl2.de/tv-programm/" . $dt->ymd( );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'html';
}


#
# 3 Zeilen pro Programm
#
# 00:00 - 15:00 # Host #
#
# <b>Title</b><br>
# Musikstyle: Stil<br>
#
# Gammel
#
sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  $ds->{SILENCE_END_START_OVERLAP}=1;
  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "05:00" );

  p( "RTL2: $chd->{xmltvid}: Processing HTML" );


  my $doc;
  eval { $doc = Html2Xml($cref); };

  if( not defined( $doc ) ) {
    error( "RTL2: $batch_id: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
  my $progs = $doc->findnodes( './/div[@class="singleBroadcast"]' );

  if( $progs->size() == 0 ) {
    error( "RTL2: $chd->{xmltvid}: No Programs found" ) ;
    return;
  }

  foreach my $prog ($progs->get_nodelist) {
      my $time = $prog->findvalue( './/span[@class="date-display-single"]' );
      my $title = $prog->findvalue( './/span[@itemprop="name"]' );
      my $eptitle = $prog->findvalue( './/span[@class="singleBroadcast-episodeTitel"]' );
      next if(norm($title) eq "");

      #print Dumper($time, $title, $eptitle);

      my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $time,
      };

      # Movie
      if(norm($title) eq "Spielfilm") {
          $ce->{program_type} = "movie";
          $ce->{title} = norm($eptitle);
      } else {
        if( norm($eptitle) =~ /^Folge (\d+)$/i )
        {
            $ce->{program_type} = "series";
            $ce->{episode} = sprintf( ". %d .", $1-1 );
        } elsif(norm($eptitle) =~ /^Folge (\d+) - (.*)$/i) {
            $ce->{program_type} = "series";
            $ce->{episode} = sprintf( ". %d .", $1-1 );
            $ce->{subtitle} = norm($2);
        }
      }

      progress( "RTL2: $chd->{xmltvid}: $time - $ce->{title}" );
      $dsh->AddProgramme( $ce );
  }

  return 1;
}


1;

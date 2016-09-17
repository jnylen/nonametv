package NonameTV::Importer::MTVxmltv;

use strict;
use warnings;

=pod

Importer for XML files sent by VIMN for MTV channels

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/norm AddCategory ParseXmltv/;
use NonameTV::Log qw/d progress error/;
use NonameTV::Config qw/ReadConfig/;
use Data::Dumper;
use NonameTV::DataStore::Helper;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  #defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}


sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};

  my $needhelper = 0;
  my $date;
  my $time;
  my $currdate = "x";

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $cref=`cat \"$file\"`;

  my $prog = ParseXmltv (\$cref, $chd->{grabber_info});
  my @shows = SortShows( @{$prog} );
  foreach my $e (@shows) {

    $e->{channel_id} = $chd->{id};

    # translate start end from DateTime to string
    $e->{start_dt}->set_time_zone ('UTC');
    $e->{start_time} = $e->{start_dt}->hms(':');
    #$e->{end_time} = $e->{stop_dt}->ymd("-")." ".$e->{stop_dt}->hms(':');

    my $date = $e->{start_dt}->ymd("-");
    if( $date ne $currdate ) {
      if( $currdate ne "x" ) {
         # save last day if we have it in memory
         #	FlushDayData( $channel_xmltvid, $dsh , @ces );
         $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      progress("MTVxmltv: $chd->{xmltvid}: Date is $date");
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;
    }

    delete $e->{start_dt};
    delete $e->{stop_dt};
    delete $e->{category};

    progress( "MTVxmltv: $chd->{xmltvid}: $e->{start_time} - $e->{title}" );

    #print Dumper($e);

    #$dsh->AddProgramme($e);
    $dsh->AddProgramme($e);
  }

  $dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub bytime {

  my( $Y1, $M1, $D1, $h1, $m1, $s1 ) = ( $$a{start_dt} =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)$/ );
  my $t1 = int( sprintf( "%04d%02d%02d%02d%02d%02d", $Y1, $M1, $D1, $h1, $m1, $s1 ) );

  my( $Y2, $M2, $D2, $h2, $m2, $s2 ) = ( $$b{start_dt} =~ /^(\d+)\-(\d+)\-(\d+)T(\d+)\:(\d+)\:(\d+)$/ );
  my $t2 = int( sprintf( "%04d%02d%02d%02d%02d%02d", $Y2, $M2, $D2, $h2, $m2, $s2 ) );

  $t1 <=> $t2;
}

sub SortShows {
  my ( @shows ) = @_;

  my @sorted = sort bytime @shows;

  return @sorted;
}


1;

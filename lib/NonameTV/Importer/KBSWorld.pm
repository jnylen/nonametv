package NonameTV::Importer::KBSWorld;

use strict;
use warnings;

=pod

Import data from KBS World

Channels: KBS World TV

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;

use NonameTV qw/norm ParseXml AddCategory AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

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

sub first_day_of_week
{
  my ($year, $week) = @_;

  # Week 1 is defined as the one containing January 4:
  DateTime
    ->new( year => $year, month => 1, day => 4, hour => 00, minute => 00, time_zone => 'UTC' )
    ->add( weeks => ($week - 1) )
    ->truncate( to => 'week' );
}

sub last_day_of_week
{
  my ($year, $week) = @_;

  # Week 1 is defined as the one containing January 4:
  DateTime
    ->new( year => $year, month => 1, day => 4, hour => 00, minute => 00, time_zone => 'UTC' )
    ->add( weeks => $week )
    ->truncate( to => 'week' )
    ->subtract( days => 1 );
}


sub Object2Url {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ( $batch_id =~ /(\d+)-(\d+)$/ );

  my $datefirst = first_day_of_week( $year, $week );
  my $datelast = last_day_of_week( $year, $week );

  my $url = sprintf("http://kbsworld.kbs.co.kr/schedule/down_schedule_db.php?down_time_add=-9&wlang=e&start_date=%s&end_date=%s", $datefirst->ymd("-"), $datelast->ymd("-"));

 progress("Fetching $url...");

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # Clean it up
  $$cref =~ s/\t+//gi;
  $$cref =~ s/\n//gi;
  $$cref =~ s/<style>(.*)<\/style>//gi;
  $$cref =~ s/<colgroup>(.*)<\/colgroup>//gi;
  $$cref =~ s/<thead>(.*)<\/thead>//gi;
  $$cref =~ s/<\/body>//gi;
  $$cref =~ s/<\/html>//gi;
  $$cref =~ s/<table border="1" cellspacing="0" class="sch_table">/<table>/g;

  $$cref =~ s/<br style='(.*?)'>/\n/g;
  $$cref =~ s/&nbsp;//gi;
  $$cref =~ s/&#39;/'/g;
  $$cref =~ s/&#65533;//g;
  $$cref =~ s/ & / &amp; /g;
  my $data = '<?xml version="1.0" encoding="utf-8"?>';
  $data .= $$cref;

  my $doc = ParseXml( \$data );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//tbody/tr" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $str = $doc->toString( 1 );
  return( \$str, undef );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( \$cref );
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//tbody/tr" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $currdate = "x";


  foreach my $p ($ns->get_nodelist)
  {
    # day
    my $dayte = ParseDate($p->findvalue( 'td[1]' ));
    if( $dayte ne $currdate ){
        progress("Date is ".$dayte);

        $dsh->StartDate( $dayte , "00:00" );
        $currdate = $dayte;
    }

    my $start = $p->findvalue( 'td[2]' );
    my $title = $p->findvalue( 'td[4]' );
    my $season = norm($p->findvalue( 'td[5]' ));
    my $genre = $p->findvalue( 'td[6]' );
    my $subgenre = $p->findvalue( 'td[7]' );
    my $episode = norm($p->findvalue( 'td[8]' ));
    my $synopsis = $p->findvalue( 'td[9]' );

    my $ce = {
        title 	  => norm($title),
        channel_id  => $chd->{id},
        description => norm($synopsis),
        start_time  => $start,
    };

    # Season Episode
    if(($season) and $season =~ /(\d+)/ and ($episode) and $episode =~ /(\d+)/) {
  		$ce->{episode} = sprintf( "%d . %d . ", $season-1, $episode-1 );
  	} elsif((!$season) and ($episode) and $episode =~ /(\d+)/) {
  		 $ce->{episode} = sprintf( " . %d . ", $episode-1 );
  	}

    # Genre
    if(defined($genre) and $genre ne "") {
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "KBSWorld", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    # Subgenre
    if(defined($subgenre) and $subgenre ne "") {
      my ( $program_type2, $category2 ) = $self->{datastore}->LookupCat( "KBSWorld", $subgenre );
      AddCategory( $ce, $program_type2, $category2 );
    }

    # Live
    if($title =~ /\[LIVE\]/i) {
      $ce->{live} = 1;
      $ce->{title} =~ s/\[LIVE\]//i;
      $ce->{title} = norm($ce->{title});
    }

    # Remove Season <num> from title
    if($title =~ /Season (\d+)$/i) {
      $ce->{title} =~ s/Season (\d+)$//i;
      $ce->{title} = norm($ce->{title});
    }

    $dsh->AddProgramme( $ce );

    progress("KBSWorld: $chd->{xmltvid}: $start - $title");
  }

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  my( $month, $day, $year );

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d\d\d\d$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d\d\d\d)$/ );
  } elsif( $text =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ ) { # format '20180326'
    $year = $1;
    $month = $2;
    $day = $3;
  }

  if(not defined($year)) {
    return undef;
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

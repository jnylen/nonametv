package NonameTV::Importer::KBSWorld;

use strict;
use warnings;

=pod

Importer for data from KBS World (http://kbsworld.kbs.co.kr/).
One file per week downloaded from their site.

Format is "Excel". It's mostly just XLSX so it's XML.

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML;

use NonameTV qw/AddCategory norm normUtf8 ParseXml/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/d progress w error f/;
use NonameTV::DataStore::Helper;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Asia/Seoul"  );
  $self->{datastorehelper} = $dsh;

  # Use augmenter, and get teh fabulous shit
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub first_day_of_week
{
  my ($year, $week) = @_;

  # Week 1 is defined as the one containing January 4:
  DateTime
    ->new( year => $year, month => 1, day => 4 )
    ->add( weeks => ($week - 1) )
    ->truncate( to => 'week' );
} # end first_day_of_week

sub FetchDataFromSite {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $datefirst = first_day_of_week( $year, $week )->add( days => 0 )->ymd('-'); # monday
  my $datelast  = first_day_of_week( $year, $week )->add( days => 6 )->ymd('-'); # sunday

  my $mech = $self->{cc}->UserAgent();

  my $response = $mech->post( "http://kbsworld.kbs.co.kr/schedule/down_schedule_.php", { 'wlang' => 'e', 'down_time_add' => '0', 'start_date' => $datefirst, 'end_date' => $datelast, 'ftype' => 'xls' } );
  my $content  = $response->content( format => 'text' );

  return ($content, undef);
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Clean it up
  $$cref =~ s/<col width="(.*?)">//g;
  $$cref =~ s/<br style='(.*?)'>/\n/g;
  $$cref =~ s/&nbsp;//g;
  $$cref =~ s/&#39;/'/g;
  $$cref =~ s/&#65533;//g;
  $$cref =~ s/ & / &amp; /g;
  $$cref =~ s/<The Return of Superman>//g;

  my $data = '<?xml version="1.0" encoding="utf-8"?>';
  $data .= $$cref;

  #print Dumper($data);

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($data); };

  if( not defined( $doc ) ) {
    f "Not well-formed xml";
    return 0;
  }

  my $ns = $doc->find( "//tbody/tr" );

  if( $ns->size() == 0 ) {
    f "No Rows found";
    return 0;
  }

  my $currdate = "x";

  # Programmes
  foreach my $row ($ns->get_nodelist) {
    my $date = norm( $row->findvalue( "td[1]" ) );
    my $time = norm( $row->findvalue( "td[2]" ) );
    my $duration = norm( $row->findvalue( "td[3]" ) );
    my $title = norm( $row->findvalue( "td[4]" ) );
    my $genre = norm( $row->findvalue( "td[5]" ) );
    my $episode = norm( $row->findvalue( "td[6]" ) );
    my $desc = norm( $row->findvalue( "td[7]" ) );

    if($date ne $currdate ) {
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("KBSWorld: Date is: $date");
    }

    my $ce = {
      channel_id => $chd->{id},
      title => norm($title),
      start_time => $time,
      description => norm($desc),
    };

    # Reason to defaulting to season 1 is that korean dramas 99% of all cases
    # only have 1 season. Variety shows goes by the prodnumber so hits up to episode 570.

    my $season = 1;

    # Try to fetch the season from the title
    if($title =~ /Season (\d+)/i and $title ne "Let's Go! Dream Team Season 2") {
        ($season) = ($title =~ /Season (\d+)/i);
        $ce->{title} =~ s/Season (\d+)//i;
        $ce->{title} = norm($ce->{title});
        $ce->{title} =~ s/-$//;
        $ce->{title} = norm($ce->{title});
    }

    if( $episode ne "" )
    {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }

    # LIVE?
    if($title =~ /\[LIVE\]/i) {
        $ce->{title} =~ s/\[LIVE\]//i;
        $ce->{title} = norm($ce->{title});

        $ce->{live} = "1";
    } else {
        $ce->{live} = "0";
    }

    progress( "KBSWorld: $chd->{xmltvid}: $time - $ce->{title}" );
    $dsh->AddProgramme( $ce );

  }

  #$dsh->EndBatch( 1 );

  return 1;
}

1;

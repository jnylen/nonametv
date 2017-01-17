package NonameTV::Importer::OKV;

use strict;
use warnings;

=pod

Importer for OKV (Öppna Kanalen Växjö).
The file downloaded is a XML-file and provides data for
one week.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;
use Math::Round 'nearest';

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

  	my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

  	$self->{MaxDays} = 8;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = 'http://okv.se/tabla.xml/'.$date;

  return( $url, undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref =~ '<!--' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programme" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programme" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }

  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "00:00" );

  foreach my $sc ($ns->get_nodelist)
  {

    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './start' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './stop' ) );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './stop' ) . "'. Skipping." );
      next;
    }

    # Data
    my $title    = norm($sc->findvalue( './title'   ));
    $title       =~ s/&amp;/&/g; # Wrong encoded char
    my $desc     = norm($sc->findvalue( './desc'    ));
    my $duration = norm($sc->findvalue( './duration'    ));

	  my $ce = {
        channel_id 		=> $chd->{id},
        title 			=> $title,
        start_time   => $start->hms(":"),
        end_time     => $end->hms(":"),
        description 	=> $desc,
    };

    my ( $dummy, $dummy2, $episode ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+)$/i ); # bugfix
    if(defined($episode)) {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    my ( $dummy3, $dummy4, $episode2, $ofepisodes ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+) av (\d+)$/i ); # bugfix
    if(defined($episode2)) {
        $ce->{episode} = sprintf( ". %d/%d .", $episode2-1, $ofepisodes );
    }

    my ( $dummy5, $dummy6, $episode3, $subtitle ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+)(\:| \-) (.*)$/i ); # bugfix
    if(defined($episode3)) {
        $ce->{episode} = sprintf( ". %d .", $episode3-1 );
        $ce->{subtitle} = norm($subtitle);
    }

    my ( $dummy7, $dummy8, $episode4, $ofepisodes2 ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+) \(av (\d+)\)$/i ); # bugfix
    if(defined($episode4)) {
        $ce->{episode} = sprintf( ". %d/%d .", $episode4-1, $ofepisodes2 );
    }

    # Clean title
    $title =~ s/, vecka (\d+)//;
    $title =~ s/, avsnitt (\d+) av (\d+)//;
    $title =~ s/, del (\d+) av (\d+)//;
    $title =~ s/, avsnitt (\d+)\: (.*)//;
    $title =~ s/, del (\d+)\: (.*)//;
    $title =~ s/, avsnitt (\d+)//;
    $title =~ s/, del (\d+)//;
    $title =~ s/, akt (\d+) \(av (\d+)\)//;
    $title =~ s/, akt (\d+)//;
    $title =~ s/ avsnitt (\d+) av (\d+)//;
    $title =~ s/ del (\d+) av (\d+)//;
    $title =~ s/ avsnitt (\d+)(\:| \-) (.*)//;
    $title =~ s/ del (\d+)\: (.*)//;
    $title =~ s/ avsnitt (\d+)//;
    $title =~ s/ del (\d+)//;

    my ( $subtitle2 ) = ($title =~ /\: (.*)$/i ); # bugfix
    if(defined($subtitle2)) {
        $ce->{subtitle} = norm($subtitle2);
    }

    $title =~ s/\: (.*)$//;

    # norm it and replace it
    $ce->{title} = norm($title);

    progress( "OKV: $chd->{xmltvid}: $start - $title" );

  	# Add Programme
  	$dsh->AddProgramme( $ce );
  }

  #$dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  my $offset = substr( $str , 15 , 5 );

  if( not defined $year )
  {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

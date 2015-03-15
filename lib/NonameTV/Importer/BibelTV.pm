package NonameTV::Importer::BibelTV;

use strict;
use warnings;

=pod

Imports data for BibelTV.

=cut

use utf8;
use Encode;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Unicode::String;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;
use File::Slurp;

use NonameTV qw/norm normUtf8 ParseXml AddCategory MonthNumber/;
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

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $filename, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  my $currdate = "x";

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_file($filename); };
  if( $@ ne "" )
  {
    error( "BibelTV: Failed to parse $@" );
    return 0;
  }

  # Find all "programme"-entries.
  my $ns = $doc->find( ".//programme" );

  foreach my $sc ($ns->get_nodelist)
  {
    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    my $date = $start->ymd("-");

    if($date ne $currdate ) {
		if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $date;
		$dsh->StartBatch( $batchid , $chd->{id} );
		$dsh->StartDate( $date , "06:00" );
		$currdate = $date;

		progress("BibelTV: Date is: $date");
	}

    #
    # end time
    #
    #my $end = $self->create_dt( $sc->findvalue( './@stop' ) );

    #
    # title
    #
    my $title = $sc->findvalue( './title' );
    $title =~ s/ amp / &amp; /g if $title; # What the hell

    #
    # subtitle
    #
    my $subtitle = $sc->findvalue( './subtitle' );
    $subtitle =~ s/ amp / &amp; /g if $subtitle; # What the hell

    #
    # genre
    #
    my $genre = $sc->getElementsByTagName('category');

    #
    # description
    #
    my $desc = $sc->findvalue( './desc' );


    progress("BibelTV: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->hms(":"),
    };

    $ce->{subtitle} = norm($subtitle) if norm($subtitle) ne norm($title);

    ## Image
    if($sc->findvalue( './icon/@src' )) {
        $ce->{fanart} = $sc->findvalue( './icon/@src' );
        $ce->{fanart} =~ s/\/s\//\/sd\//;
    }

    # Aspect (It's actually in the correct form)
	my ($aspect) = $sc->findvalue ('./video/aspect');
	$ce->{aspect} = norm($aspect) if $aspect;

    # The director and actor info are children of 'credits'
    my (@actors, @directors, @guests, @presenters);

    foreach my $dir ($sc->getElementsByTagName( 'director' ))
    {
        push(@directors, norm($dir->textContent()));
    }
    foreach my $act ($sc->getElementsByTagName( 'actor' ))
    {
        push(@actors, norm($act->textContent()));
    }
    foreach my $act ($sc->getElementsByTagName( 'guest' ))
    {
        push(@guests, norm($act->textContent()));
    }
    foreach my $act ($sc->getElementsByTagName( 'presenter' ))
    {
        push(@presenters, norm($act->textContent()));
    }
    $ce->{actors} = join( ";", grep( /\S/, @actors ) );
    $ce->{directors} = join( ";", grep( /\S/, @directors ) );
    $ce->{guests} = join( ";", grep( /\S/, @guests ) );
    $ce->{presenters} = join( ";", grep( /\S/, @presenters ) );

    # Episodes
    if(my($episode2) = ($sc->findvalue ('./episode-num') =~ /Folge\s+(\d+)/i)) {
        $ce->{episode} = sprintf( " . %d .", $episode2-1 );
    }


    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  #print("Date >$str<\n");

  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  #my $second = substr( $str , 12 , 2 );
  #my $offset = substr( $str , 15 , 5 );


  if( not defined $year )
  {
    return undef;
  }
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Berlin', # Canada
                          );
  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

package NonameTV::Importer::TVE;

use strict;
use warnings;

=pod

Imports data 

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use Text::Unidecode;
use File::Slurp;
use Encode;

use NonameTV qw/ParseXmlFile Wordfile2Xml norm Html2Xml AddCategory MonthNumber AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Madrid" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.html$/i ) {
    $self->ImportHTML( $file, $chd );
  } elsif( $file =~ /\.doc$/i ) {
    if( $chd->{xmltvid} =~ /(la1|la2)/ ) {
      $self->ImportDualWord( $file, $chd );
    } else {
      $self->ImportWord( $file, $chd );
    }
  }


  return;
}

sub ImportDualWord
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "TVE: $chd->{xmltvid}: Processing Word $file" );

  my $doc = Wordfile2Xml($file);

  # Find all paragraphs.
  my $ns = $doc->find( "//p" );

  if( $ns->size() == 0 ) {
    error "No P:s found";
    return 0;
  }

  my $currdate = "x";
  my $chdname = $chd->{display_name};

  foreach my $progs ($ns->get_nodelist) {
    my $content  = norm($progs->textContent);
    #print Dumper($content);
    
    if($content =~ /PROGRAMACI.N/i and $content =~ /(\d+) DE (.*?)$/ ) {
      my $daynum = $1;
      my $monthname = $2;

      #print("content: $content\n");

      # Channel?
      if($content =~ m|($chdname)|i) {
        #print("match: $chdname\n");

        # Date
        my $month = MonthNumber($monthname, "es");
        my $year = DateTime->now->year();
        my $date = ParseDate("$daynum\.$month\.$year");
        
        # Date
        if($date ne $currdate ) {
          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batchid = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batchid , $chd->{id} );
          $dsh->StartDate( $date , "00:00" );
          $currdate = $date;
          
          progress("TVE: Date is: " . $date);
        }
      } elsif($currdate ne "x") {
        $dsh->EndBatch( 1 );
        $currdate = "x";
      }
    } elsif($content =~ /^(\d\d\:\d\d) (.*)/ and $currdate ne "x") {
      # Event
      my $time = ParseTime($1);

      # Programme
      my $ce = {
        title       	 => norm($2),
        start_time  	 => $time,
      };

      progress( "TVE: $chd->{xmltvid}: " . $dsh->{curr_date}->ymd("-") . " $time - " . $ce->{title} );
      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ImportWord
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "TVE: $chd->{xmltvid}: Processing Word $file" );

  my $doc = Wordfile2Xml($file);

  # Find all paragraphs.
  my $ns = $doc->find( "//p" );

  if( $ns->size() == 0 ) {
    error "No P:s found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
    my $content  = norm($progs->textContent);
    
    if($content =~ /(\d+) DE (.*?) DE (\d\d\d\d)$/) {
      # Date
      my $month = MonthNumber($2, "es");
      my $date = ParseDate("$1\.$month\.$3");
      
      # Date
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
        
        progress("TVE: Date is: " . $date);
      }
    } elsif($content =~ /^(\d\d\:\d\d).(.*)/) {
      # Event
      my $time = ParseTime($1);

      # Programme
      my $ce = {
        title       	 => norm($2),
        start_time  	 => $time,
      };

      progress( "TVE: $chd->{xmltvid}: " . $dsh->{curr_date}->ymd("-") . " $time - " . $ce->{title} );
      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "TVE: $chd->{xmltvid}: Processing XML $file" );

  my $doc = ParseXmlFile($file);

  # Find all paragraphs.
  my $ns = $doc->find( "//Event" );

  if( $ns->size() == 0 ) {
    error "No Events found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
    my $datetime  = $self->create_dt($progs->findvalue( '@beginTime' ));

    # Date
    if($datetime->ymd("-") ne $currdate ) {
      if( $currdate ne "x" ) {
      #  $dsh->EndBatch( 1 );
      } else {
        my $batchid = $chd->{xmltvid} . "_" . $datetime->ymd("-");
        $dsh->StartBatch( $batchid , $chd->{id} );
      }

      $dsh->StartDate( $datetime->ymd("-") , "00:00" );
      $currdate = $datetime->ymd("-");

      progress("TVE: Date is: " . $datetime->ymd("-"));
    }

    my $title_org = $progs->findvalue( './EpgProduction/EpgText/ExtendedInfo[@name="Original Event Name"]' );
    my $eptitle_org = $progs->findvalue( './EpgProduction/EpgText/ExtendedInfo[@name="Original Episode Name"]' );

    my $title = $progs->findvalue( './EpgProduction/EpgText/Name' );
    my $eptitle = $progs->findvalue( './EpgProduction/EpgText/ExtendedInfo[@name="Episode Name"]' );
    my $epnr = $progs->findvalue( './EpgProduction/EpgText/ExtendedInfo[@name="Episode Number"]' );
    my $shortdesc = $progs->findvalue( './EpgProduction/EpgText/ShortDescription' );
    my $desc = $progs->findvalue( './EpgProduction/EpgText/ShortDescriptionDescription' );

    # Programme
    my $ce = {
      title       	 => norm($title) || norm($title_org),
      description    => norm($desc) || norm($shortdesc),
      start_time  	 => $datetime->hms(":"),
    };

    # Epnr
    if(norm($epnr) ne "" and $epnr =~ /(\d+)/) {
      $ce->{episode} = sprintf( ". %d .", $1-1 );
    }

    # Eptitle
    if(norm($eptitle) ne "" || norm($eptitle_org) ne "") {
      $ce->{subtitle} = norm($eptitle) if(norm($eptitle) ne "" and norm($eptitle) ne $ce->{title});
      $ce->{subtitle} = norm($eptitle_org) if(norm($eptitle_org) ne "" and !defined($ce->{subtitle}) and norm($eptitle_org) ne $ce->{title});
    }

    progress( "TVE: $chd->{xmltvid}: $datetime - " . $ce->{title} );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ImportHTML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "TVE: $chd->{xmltvid}: Processing HTML $file" );

  my $cref=`cat \"$file\"`;
  $cref =~ s|<\/HEAD>|<\/HEAD><BODY>|g;

  $cref =~ s|
  ||g;

  my $doc = Html2Xml($cref);

  # Find all paragraphs.
  my $ns = $doc->find( "//p" );

  if( $ns->size() == 0 ) {
    error "No P:s found";
    return 0;
  }

  my $currdate = "x";

  foreach my $progs ($ns->get_nodelist) {
    my $content  = $progs->textContent;

    # Date?
    if(norm($content) =~ /^PROGRAMACION/i and norm($content) =~ /(\d+) DE (.*?) DE (\d\d\d\d)$/) {
      my $month = MonthNumber($2, "es");
      my $date = ParseDate("$1\.$month\.$3");
      
      # Date
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
        
        progress("TVE: Date is: " . $date);
      }

    } elsif(norm($content) =~ /^(\d\d\:\d\d) (.*)/) {
      my $time = ParseTime($1);

      # Programme
      my $ce = {
        title       	 => norm($2),
        start_time  	 => $time,
      };

      progress( "TVE: $chd->{xmltvid}: $time - " . $ce->{title} );
      $dsh->AddProgramme( $ce );
    } else {
      # Description
    }
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+\.\d+\.\d\d\d\d$/ ) { # format '07.09.2017'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d\d\d\d)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text2 ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min );

  if( $text2 =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text2 =~ /^(\d+):(\d+)$/ );
  }

  if($hour >= 24) {
  	$hour = $hour-24;

  	#print("Hour: $hour\n");
  }

  return sprintf( "%02d:%02d", $hour, $min );
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my($year, $month, $day, $hour, $minute) = ($str =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/);

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Madrid',
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;

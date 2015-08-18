package NonameTV::Importer::DreiPlus;

use strict;
use warnings;

=pod

Import data for 3 Plus TV Network AG in Switzerland.
Channels: 3+, 4+ and 5+

Features:

=cut

use utf8;

use DateTime;
use Data::Dumper;
use XML::LibXML;
use IO::Scalar;
use Archive::Zip qw/:ERROR_CODES/;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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
    error( "DreiPlus: Unknown file format: $file" );
  }

  return;
}


sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "DreiPlus: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//sendeTag/programmElement" );

  if( $rows->size() == 0 ) {
    error( "DreiPlus: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  my $week = $doc->findvalue('./programmwoche/@pw');
  my $year_long = $doc->findvalue('./programmwoche/@ersterTag');
  my ($year) = ($year_long =~ /^(\d\d\d\d)/);

  if(!defined $year) {
    error( "DreiPlus: $chd->{xmltvid}: Failure to get year from file content" ) ;
    return;
  } else { $year += 2000; }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  foreach my $row ($rows->get_nodelist) {
    my $date = $row->findvalue( './/header/kdatum' );
    my $starttime = $row->findvalue( './/header/szeit' );
    my $rerun = $row->findvalue( './@rerun' );

    # Date
    if($date ne $currdate ) {
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("DreiPlus: Date is: $date");
    }

    # Titles
    my $stitle = $row->findvalue( './/header/stitel' );
    $stitle =~ s/^(Neue Folge!|Free-TV-Premiere) //i;
    my $otitle = $row->findvalue( './/header/otitel' );
    my $subtitle = $row->findvalue( './/header/epistitel' );
    my $osubtitle = $row->findvalue( './/header/oepistitel' );

    # Extra
    my $genre = $row->findvalue( './/header/genre' );
    my $year = $row->findvalue( './/header/produktionsjahr' );

    # Desc
    my $desc = $row->findvalue( 'langInhalt' );

    my $ce = {
      channel_id => $chd->{id},
      title => norm($stitle),
      start_time => $date . " " . $starttime,
      description => norm($desc),
    };

    # Subtite
    if($subtitle ne "") {
        $ce->{subtitle} = norm($subtitle);

        if( my ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) - Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
            $ce->{subtitle} = undef;
        }

        $ce->{program_type} = 'series';
    }



    # Genres
    if($genre ne "") {
      my($program_type, $category ) = $ds->LookupCat( 'DreiPlus', $genre );
	  AddCategory( $ce, $program_type, $category );
    }

    # Actors
    my @actors;
    my @directors;
    my @writers;

    my $ns2 = $row->find( './/mitwirkende//darsteller' );
    foreach my $act ($ns2->get_nodelist)
    {
		my $name = norm( $act->findvalue('./pname') );

        # Role played - TODO: Add rolename to the actor
        if( $act->findvalue('./rname') and norm($act->findvalue('./rname')) ne "" ) {
        	my $name .= " (".norm( $act->findvalue('./rname') ).")";
        }

        push @actors, $name;
    }

	if( scalar( @actors ) > 0 )
	{
		$ce->{actors} = join ";", @actors;
    }

    my $ns3 = $row->find( './/mitwirkende//stab' );
    foreach my $stab ($ns3->get_nodelist)
    {
    	my $name = norm( $stab->findvalue('./pname') );
    	$name =~ s/, /;/;

        # Type
        my $type = norm( $stab->findvalue('./@funktion') );

		# Directors
		if($type eq "Regie") {
			push @directors, $name;
			$ce->{program_type} = 'movie';
		}

		# Writers
        if($type eq "Drehbuch") {
			push @writers, $name;
		}
    }

    if( scalar( @directors ) > 0 )
    {
        $ce->{directors} = join ";", @directors;
    }

    if( scalar( @writers ) > 0 )
    {
        $ce->{writers} = join ";", @writers;
    }

    # Extra data
    $ce->{original_title} = norm($otitle) if $otitle and $otitle ne $stitle;
    $ce->{original_subtitle} = norm($osubtitle) if $osubtitle and $subtitle ne $osubtitle;

    # Year
    if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # Find rerun-info
	  if( $rerun eq "ja" )
	  {
	    $ce->{new} = "0";
	  }
	  else
	  {
	    $ce->{new} = "1";
	  }

    # Add programme
    $ds->AddProgrammeRaw( $ce );
    progress( "DreiPlus: $chd->{xmltvid}: $ce->{start_time} - $stitle" );
  } # next row

  $dsh->EndBatch( 1 );

  return 1;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

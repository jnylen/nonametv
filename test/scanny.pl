#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;
use Data::Dumper;

my $ce = {
};

my $text = "Valheita vai ei. Kausi 5, 18/23. Lisa Vanderpump ei anna Brandin lyöntiä hänelle anteeksi. Brandi jättää viimeisen matkaillan päivällisen väliin, sillä mieluummin aikaisemmin iskemänsä nuoren miehen kuin vaihdevuosissa olevia leidejä. Seurueen palattua Kim tapaa Adriennen. Kyle kauhistuu kuultuaan mitä Brandi on sanonut Kimistä muille. Hän kutsuu siskonsa uuteen taloonsa ja paljastaa hänelle, mitä tämän muka paras ystävä on sanonut, mutta Kim syyttää häntä valehtelusta.";
my @sentences = (split_text( $text ), "");
my $season = "0";
my $episode = "0";
my $eps = "0";

for( my $i2=0; $i2<scalar(@sentences); $i2++ )
{
	if( my( $seasontextnum ) = ($sentences[$i2] =~ /^Kausi (\d+)\./ ) )
	{
		$season = $seasontextnum;

		# Only remove sentence if it could find a season
		if($season ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $seasontextnum12 ) = ($sentences[$i2] =~ /^Säsong (\d+)\./i ) )
	{
		$season = $seasontextnum12;

		# Only remove sentence if it could find a season
		if($season ne "") {
			$sentences[$i2] = "";
		}
	} elsif( my( $seasontextnum11, $episoder, $ofepisodess ) = ($sentences[$i2] =~ /^Säsong (\d+), del (\d+)\/(\d+)\./i ) )
	{
		$season = $seasontextnum11;
		$episode = $episoder;
		$eps = $ofepisodess;

		# Only remove sentence if it could find a season
		if($season ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $seasontextnum9 ) = ($sentences[$i2] =~ /^(\d+) säsongen\./i ) )
	{
		$season = $seasontextnum9;

		# Only remove sentence if it could find a season
		if($season ne "") {
			$sentences[$i2] = "";
		}
	}
	elsif( my( $dummy4 ) = ($sentences[$i2] =~ /^S(\s*)songsstart\./i ) )
	{
		$sentences[$i2] = "";
	}elsif( my( $episodetextnum5, $ofepisode3 ) = ($sentences[$i2] =~ /^(\d+)\/(\d+)\./ ) )
	{
		$episode = $episodetextnum5;
		$eps = $ofepisode3;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum4, $ofepisode2 ) = ($sentences[$i2] =~ /Del (\d+)\/(\d+)\./i ) )
	{
		$episode = $episodetextnum4;
		$eps = $ofepisode2;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum8, $ofepisode8, $epititle2 ) = ($sentences[$i2] =~ /^Del (\d+) av (\d+)\:(.*)\./i ) )
	{
		$episode = $episodetextnum8;
		$eps = $ofepisode8;
		$ce->{subtitle} = norm($epititle2);

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum11, $ofepisode11) = ($sentences[$i2] =~ /^(\d+)\/(\d+)\./ ) )
	{
		$episode = $episodetextnum11;
		$eps = $ofepisode11;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum12, $ofepisode12) = ($sentences[$i2] =~ /^Jakso (\d+)\/(\d+)\./ ) )
	{
		$episode = $episodetextnum12;
		$eps = $ofepisode12;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum14) = ($sentences[$i2] =~ /^Jakso (\d+)\./ ) )
	{
		$episode = $episodetextnum14;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum13, $ofepisode13) = ($sentences[$i2] =~ /^Avsnitt (\d+)\/(\d+)\./ ) )
	{
		$episode = $episodetextnum13;
		$eps = $ofepisode13;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum16, $ofepisode16) = ($sentences[$i2] =~ /^Osa (\d+)\/(\d+)\./ ) )
	{
		$episode = $episodetextnum16;
		$eps = $ofepisode16;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum7, $ofepisode7, $epititle ) = ($sentences[$i2] =~ /^Del (\d+)\/(\d+)\:(.*)\./i ) )
	{
		$episode = $episodetextnum7;
		$eps = $ofepisode7;
		$ce->{subtitle} = norm($epititle);

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum2, $ofepisode ) = ($sentences[$i2] =~ /Del (\d+) av (\d+)/i ) )
	{
		$episode = $episodetextnum2;
		$eps = $ofepisode;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $seasonerino, $eperino1, $ofepirino1 ) = ($sentences[$i2] =~ /^Kausi (\d+), (\d+)\/(\d+)\./i ) )
	{
		$episode = $eperino1;
		$eps = $ofepirino1;
		$season = $seasonerino;

		# Only remove sentence if it could find a season
		if($eperino1 ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum3 ) = ($sentences[$i2] =~ /^Del (\d+)\./i ) )
	{
		$episode = $episodetextnum3;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum15 ) = ($sentences[$i2] =~ /^Avsnitt (\d+)\./i ) )
	{
		$episode = $episodetextnum15;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	}elsif( my( $episodetextnum ) = ($sentences[$i2] =~ /^Osa (\d+)\./ ) )
	{
		$episode = $episodetextnum;

		# Only remove sentence if it could find a season
		if($episode ne "") {
			$sentences[$i2] = "";
		}
	} elsif( my( $directors ) = ($sentences[$i2] =~ /^Ohjaus:\s*(.*)\./) )
	{
		$ce->{directors} = parse_person_list( $directors );
		$sentences[$i2] = "";
	} elsif( my( $directors8 ) = ($sentences[$i2] =~ /^Ohjaaja:\s*(.*)\./) )
	{
		my ($prodyear) = ($sentences[$i2] =~ /(\d\d\d\d)$/);
		$ce->{production_date} = $prodyear."-01-01" if defined $prodyear and $prodyear ne "";
		$ce->{directors} = parse_person_list( $directors8 );
		$sentences[$i2] = "";
	}elsif( my( $directors4 ) = ($sentences[$i2] =~ /^O:\s*(.*)\./) )
	{
		$ce->{directors} = parse_person_list( $directors4 );
		$sentences[$i2] = "";
	}elsif( my( $actors5 ) = ($sentences[$i2] =~ /^P:\s*(.*)\./ ) )
	{
		#$ce->{actors} = parse_person_list( $actors5 ); # not sure if producer or actor
		$sentences[$i2] = "";
	}elsif( my( $actors ) = ($sentences[$i2] =~ /^Pääosissa:\s*(.*)\./ ) )
	{
		$ce->{actors} = parse_person_list( $actors );
		$sentences[$i2] = "";
	}elsif( my( $directors7 ) = ($sentences[$i2] =~ /^R:\s*(.*)\./) )
	{
		$ce->{directors} = parse_person_list( $directors7 );
		$sentences[$i2] = "";
	}elsif( my( $actors7 ) = ($sentences[$i2] =~ /^S:\s*(.*)\./ ) )
	{
		$ce->{actors} = parse_person_list( $actors7 );
		$sentences[$i2] = "";
	}elsif( my( $actors9 ) = ($sentences[$i2] =~ /^Programledare:\s*(.*)\./ ) )
	{
		$ce->{presenters} = parse_person_list( $actors9 );
		$sentences[$i2] = "";
	}

	elsif( my( $directors2 ) = ($sentences[$i2] =~ /^Regi:\s*(.*)\./) )
	{
		$ce->{directors} = parse_person_list( $directors2 );
		$sentences[$i2] = "";
	}
	elsif( my( $directors3 ) = ($sentences[$i2] =~ /^Regi\s*(.*)\./) )
	{
		$ce->{directors} = parse_person_list( $directors3 );
		$sentences[$i2] = "";
	}
	elsif( my( $writers2 ) = ($sentences[$i2] =~ /^Manus:\s*(.*)\./) )
	{
		$ce->{writers} = parse_person_list( $writers2 );
		$sentences[$i2] = "";
	}
	elsif( my( $actors2 ) = ($sentences[$i2] =~ /^I rollerna:\s*(.*)\./ ) )
	{
		$ce->{actors} = parse_person_list( $actors2 );
		$sentences[$i2] = "";
	}
	elsif( my( $actors3 ) = ($sentences[$i2] =~ /^I huvudrollerna:\s*(.*)\./ ) )
	{
		$ce->{actors} = parse_person_list( $actors3 );
		$sentences[$i2] = "";
	}
	elsif( my( $actors6 ) = ($sentences[$i2] =~ /^I huvudrollerna\s*(.*)\./ ) )
	{
		$ce->{actors} = parse_person_list( $actors6 );
		$sentences[$i2] = "";
	}

	# Clean it up
	elsif( my( $rerun, $dummerinoerino3 ) = ($sentences[$i2] =~ /^\(R\)\./ ) )
	{
		$sentences[$i2] = "";
	}
	elsif( my( $dunno, $dummerinoerino2 ) = ($sentences[$i2] =~ /^\(U\)\./ ) )
	{
		$sentences[$i2] = "";
	}
	elsif( my( $hdtv, $dummerinoerino ) = ($sentences[$i2] =~ /^HD\.$/ ) )
	{
		$ce->{quality} = "HDTV";
		$sentences[$i2] = "";
	}
	elsif( my( $swelang ) = ($sentences[$i2] =~ /^SV\.$/ ) )
	{
		$sentences[$i2] = "";
	}
	elsif( my( $numberino ) = ($sentences[$i2] =~ /^\((\d+)'\)\.$/ ) )
	{
		$sentences[$i2] = "";
	}
	elsif( my( $nelonenpaketti ) = ($sentences[$i2] =~ /www\.nelonenpaketti\.fi\.$/ ) )
	{
		$sentences[$i2] = "";
	}
	elsif( my( $runtime ) = ($sentences[$i2] =~ /^(\d+)\s+min\.$/ ) )
	{
		$sentences[$i2] = "";
	}
}

# Episode info in xmltv-format
if( ($episode ne "0") and ( $eps ne "0") and ( $season ne "0") )
{
	$ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $eps );
}
elsif( ($episode ne "0") and ( $eps ne "0") )
{
	$ce->{episode} = sprintf( ". %d/%d .", $episode-1, $eps );
}
elsif( ($episode ne "0") and ( $season ne "0") )
{
	$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
}
elsif( $episode ne "0" )
{
	$ce->{episode} = sprintf( ". %d .", $episode-1 );
}

print Dumper($ce);

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm()
  # Replace newlines followed by a capital with space and make sure that there
  # is a dot to mark the end of the sentence.
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([\(A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

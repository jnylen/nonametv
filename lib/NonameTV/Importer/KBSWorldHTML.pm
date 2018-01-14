package NonameTV::Importer::KBSWorldHTML;

use strict;
use warnings;

=pod

Importer för ARIRANG airing worlwide.

=cut

use HTML::Entities;
use HTML::TableExtract;
use HTML::Parse;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Unicode::String;
use Data::Dumper;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV qw/Html2Xml norm AddCategory/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Asia/Seoul" );
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

  my $url = "http://kbsworld.kbs.co.kr/schedule/schedule_tv.php?lang=e&time_add=0&sdate=" . $dt->ymd( );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  # FIXME convert latin1 to utf-8 to HTML
  $cref = Unicode::String::latin1 ($cref)->utf8 ();
  $cref = encode_entities ($cref, "\200-\377");

  $cref =~ s|^.+(<table>.+</table>)</div></div><div.+$|<html><body>$1</body></html>|s;

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html.gz';
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
  my( $date ) = ($batch_id =~ /_(.*)$/);
  $dsh->StartDate( $date, "00:00" );

  my $te = HTML::TableExtract->new(
    keep_html => 1
  );

  $te->parse($$cref);

  my $table = $te->table(0, 0);

  for (my $i = 0; $i < $table->row_count(); $i += 1) {
    my @row       = $table->row($i);
    my ( $hour, $minute ) = ( $row[0] =~ m|(\d+):(\d+)| );
    if(!defined($hour)) {
      next;
    }
    my $data       = $row[1];
    my $genre      = $row[2];
    my $episodenum = $row[3];

    # meta
    my ( $title ) = ( $data =~ m|<strong>(.*)</strong>| );

    next if norm($title) eq "";

    my $ce = {
        channel_id  => $chd->{id},
	      title       => norm($title),
	      start_time  => $hour . ":" . $minute,
      };


    # Live
    if( $title =~ /[LIVE]/ ) {
      $ce->{title} =~ s/\[LIVE\]//;
      $ce->{title} = norm($ce->{title});
      $ce->{live} = "1";
    } else {
      $ce->{live} = "0";
    }

    # Episode number
    if(defined($episodenum)) {
      $ce->{episode} = sprintf( " . %d .", $episodenum-1 );
    }

    # Genre
    if( $genre ){
  			my($program_type, $category ) = $ds->LookupCat( 'KBSWorld', $genre );
  			AddCategory( $ce, $program_type, $category );
  	}

    p( "KBSWorldHTML: $chd->{xmltvid}: $ce->{start_time} - $ce->{title}" );
    $dsh->AddProgramme( $ce );
  }

  return 1;
}


1;

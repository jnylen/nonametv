package NonameTV::Importer::Tele5;

use strict;
use warnings;
use Encode qw/from_to/;

=pod

channels: Tele5
country: Germany

Import data from Richtext-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use DateTime;
use RTF::Tokenizer;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d progress error f/;
use NonameTV qw/AddCategory MonthNumber norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  if (!defined $self->{ServerInDeAtCh}) {
    warn 'Programme sysnopsis may only be stored on servers in germany, austria and switzerland. Set ServerInDeAtCh to yes or no.';
    $self->{ServerInDeAtCh} = 'no';
  }
  if ($self->{ServerInDeAtCh} eq 'yes') {
    $self->{KeepDesc} = 1;
  }

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

return if ( $file !~ /Tele_5_Pw_[[:digit:]]+A\.rtf/i );

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  $self->ImportRTF ($file, $chd);

  return;
}

sub ImportRTF {
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "Tele5: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $tokenizer = RTF::Tokenizer->new( file => $file );

  if( not defined( $tokenizer ) ) {
    error( "Tele5 $file: Failed to parse" );
    return;
  }

  my $text = '';
  my $textfull = 0;
  my $date;
  my $currdate = undef;
  my $title;
  my $havedatetime = 0;

  my $gotbatch;
  my $laststart;

  my $copyrightstring = "\n" . chr(169) . ' by Tele5' . chr(174);
  from_to ($copyrightstring, "windows-1252", "utf8");
  

  while( my ( $type, $arg, $param ) = $tokenizer->get_token( ) ){

    last if $type eq 'eof';

    if( ( $type eq 'control' ) and ( $arg eq 'par' ) ){
      $text .= "\n";
    } elsif( $type eq 'text' ){
      $text .= ' ' . $arg;
    }

    if( $text =~ m|\n\n\n$| ){
      $text =~ s|^\s+||m;
      $text =~ s|\s+$||m;
      $text =~ s|\n+$||;

      # got one block, either a new day or one program
      if ($text =~ m|Tele 5, Programmwoche|) {
        my ($week, $daystring) = ($text =~ m|Tele 5 PW: (\d+) ([^\n]*)\n|s);
        my ($day, $month, $year) = ($daystring =~ m|(\d+)\. (\S+) (\d+)|);

        if (!$gotbatch) {
          $gotbatch = 1;
          $self->{datastore}->StartBatch ($chd->{xmltvid} . '_' . $year . '-' . sprintf("%02d", $week));
        }

        $month = MonthNumber ($month, 'de');
        $currdate = DateTime->new (
          year => $year,
          month => $month,
          day => $day,
          time_zone => 'Europe/Berlin');
        progress "new day: $daystring == " . $currdate->ymd('-');
        $laststart = undef;
#        d "DAY: $text";
      } else { 
        d "TEXT: $text";
        from_to ($text, "windows-1252", "utf8");

        # start_time and title
        my ($hour, $minute, $title) = ($text =~ m |^\s*(\d{2}):(\d{2})\s+(.*)$|m);
        if (!defined ($hour)) {
          f ('program without start time');
        }
        my $starttime = $currdate->clone();
        $starttime->set_hour ($hour);
        $starttime->set_minute ($minute);
        $starttime->set_time_zone ('UTC');
        if (!$laststart) {
          $laststart = $starttime->clone();
        }
        if (DateTime->compare ($laststart, $starttime) == 1) {
          $starttime->add (days => 1);
          $currdate->add (days => 1);
        }
        my $ce = {
          channel_id => $chd->{id},
          start_time => $starttime->ymd('-') . ' ' . $starttime->hms(':'),
        };

        # episode number
        my ($episodenum) = ($text =~ m |^\s*Folge\s+(\d+)$|m);
        if ($episodenum) {
          $ce->{episode} = ' . ' . ($episodenum - 1) . ' . ';

          # episode title
          my ($episodetitle) = ($text =~ m |\n(.*)\n\s*Folge\s+\d+\n|);
          # strip orignal episode title if present
          #error 'episode title: ' . $episodetitle;
          $episodetitle =~ s|\(.*\)||;
          $ce->{subtitle} = $episodetitle;
        } else {
          # seems to be a movie, maybe it's a multi part movie
          if ($title =~ m|Teil|) {
            my ($partnum) = ($title =~ m|[,-] Teil (\d+)$|);
            $title =~ s|[,-] Teil \d+$||;
            $ce->{episode} = ' . . ' . ($partnum - 1);
          }
        }

        # year of production and genre/program type
        my ($genre, $production_year) = ($text =~ m |\n\s*(.*)\n\s*Produziert:\s+.*\s(\d+)|);
        if ($production_year) {
          $ce->{production_date} = $production_year . '-00-00';
        }
        if ($genre) {
          if (!($genre =~ m|^Sendedauer:|)) {
            my ($program_type, $categ) = $ds->LookupCat ('Tele5', $genre);
            AddCategory ($ce, $program_type, $categ);
          }
        }

        # synopsis
        if ($self->{KeepDesc}) {
          my ($desc) = ($text =~ m|^.*\n\n(.*?)$|s);
          if ($desc) {
            $ce->{description} = $desc . $copyrightstring;
          }
        }

        # aspect
        if ($text =~ m|^\s*Bildformat 16:9$|m) {
          $ce->{aspect} = '16:9';
        }

        # category override for kids (as we don't have a good category for anime anyway)
        if ($text =~ m|^\s*KINDERPROGRAMM$|m) {
          $ce->{category} = 'Kids';
        }

        # program type movie (hard to guess it from the genre)
        if ($text =~ m|^\s*Film$|m) {
          $ce->{program_type} = 'movie';
        }

        #
        if ($text =~ m|^\s*Kirchenprogramm$|m) {
          $ce->{program_type} = 'tvshow';
        }

        # program_type and category for daily shows
        if ($title eq 'Homeshopping') {
          $ce->{program_type} = 'tvshow';
        } elsif ($title eq 'Making of eines aktuellen Kinofilms') {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        } elsif ($title =~ m|^Wir lieben Kino|) {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        } elsif ($title =~ m|^Gottschalks Filmkolumne|) {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        }

        # directors
        my ($directors) = ($text =~ m|^\s*Regie:\s*(.*)$|m);
        if ($directors) {
          $ce->{directors} = $directors;
        }

        $ce->{title} = $title;
        $self->{datastore}->AddProgramme ($ce);
      }
      $text = '';
    }
  }

  $self->{datastore}->EndBatch (1, undef);
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
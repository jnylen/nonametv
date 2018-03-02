package NonameTV::Importer::BBCWW_mail;

use strict;
use warnings;

=pod
Importer for BBC Worldwide

Channels: BBC Entertainment, BBC Knowledge, BBC HD, BBC Lifestyle, CBeebies

The excel files is downloaded from BBCWWChannels.com

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use Data::Dumper;

use NonameTV qw/norm ParseExcel formattedCell MonthNumber/;
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

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xls|xlsx)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "BBCWW: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  # Depending on what timezone
  my $dsh = undef;
  if($chd->{grabber_info} eq "Finland") {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "EET" );
  } elsif($chd->{grabber_info} ne "") {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  } else {
    $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  }
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "BBCWW_mail: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    my $grabberino = $chd->{grabber_info};

    # worksheets
    # main worksheet is "Schedule" if thats not the right one, jump to "Hungary"
    if( $oWkS->{label} !~ /$grabberino/ ){
      progress( "BBCWW: $chd->{xmltvid}: Skipping worksheet: $oWkS->{label}" );
      next;
     }

    progress( "BBCWW: $chd->{xmltvid}: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
      			$columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /English Title/ );
      			$columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Programme Title/ );
      			$columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Programme \(English\)$/ );

            $columns{'ORGTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /English Title/ );
			      $columns{'ORGTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Programme \(English\)$/ );

            $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /English Episode Title/ and not defined $columns{'Episode Title'} );
            $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name \(English\)/ and not defined $columns{'Episode Title'} );
            $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Title/ and not defined $columns{'Episode Title'} );
            $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name/ and not defined $columns{'Episode Title'} );

            $columns{'Ser No'} = $iC if( $oWkS->cell($iC, $iR) =~ /Series No./ );
            $columns{'Ser No'} = $iC if( $oWkS->cell($iC, $iR) =~ /Series Number/ );
            $columns{'Ep No'}  = $iC if( $oWkS->cell($iC, $iR) =~ /Episode No./ );
            $columns{'Ep No'}  = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Number/ );
            $columns{'Eps'}    = $iC if( $oWkS->cell($iC, $iR) =~ /Episodes in/ );

            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /Date/ and $oWkS->cell($iC, $iR) !~ /EET/ and $oWkS->cell($iC, $iR) !~ /IST/ );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /Time/ and $oWkS->cell($iC, $iR) !~ /EET/ and $oWkS->cell($iC, $iR) !~ /IST/ ); # Dont set the time to EET
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /Time \(CET\/CEST\)/ );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /Time \(UTC\)/ );

            $columns{'Year'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Production Year/ );
            $columns{'Director'}  = $iC if( $oWkS->cell($iC, $iR) =~ /Director/ );
            $columns{'Cast'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Cast/ );
            $columns{'Presenter'} = $iC if( $oWkS->cell($iC, $iR) =~ /Presenter/ );

            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /English Synopsis/ and not defined $columns{'Synopsis'} );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis \(English\)/ and not defined $columns{'Synopsis'} );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Synopsis\.$/ and not defined $columns{'Synopsis'} );

            # Swedish
      			if($chd->{sched_lang} eq "sv") {
      			    $columns{'Title'}         = $iC if( $oWkS->cell($iC, $iR) =~ /Programme \(Swedish\)/ );
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis \(Swedish\)/ );
      			    $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name \(Swedish\)/ );
      			}elsif($chd->{sched_lang} eq "no") {
                $columns{'Title'}         = $iC if( $oWkS->cell($iC, $iR) =~ /Programme \(Norwegian\)/ );
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis \(Norwegian\)/ );
      			    $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name \(Norwegian\)/ );
      			}elsif($chd->{sched_lang} eq "da") {
                $columns{'Title'}         = $iC if( $oWkS->cell($iC, $iR) =~ /Programme \(Danish\)/ );
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis \(Danish\)/ );
      			    $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name \(Danish\)/ );
      			}elsif($chd->{sched_lang} eq "fi") {
                $columns{'Title'}         = $iC if( $oWkS->cell($iC, $iR) =~ /Programme \(Finnish\)/ );
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis \(Finnish\)/ );
      			    $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Episode Name \(Finnish\)/ );
                $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /Date/ and $oWkS->cell($iC, $iR) =~ /EET/ );
                $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /Time/ and $oWkS->cell($iC, $iR) =~ /EET/ );
      			}elsif($chd->{sched_lang} eq "en") {
                $columns{'Title'}         = $iC if( $oWkS->cell($iC, $iR) =~ /^Programme Title$/ );
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /English Synopsis/ );
      			    $columns{'Episode Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Episode Title$/ );
      			}elsif($chd->{sched_lang} eq "nl") {
      			    $columns{'Synopsis'}      = $iC if( $oWkS->cell($iC, $iR) =~ /Dutch Synopsis/ );
      			}

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Date/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      my $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR));
      next if( ! $date );

	    # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			    $dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("BBCWW: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	    # time
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);
      next if( ! $time );

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);
      next if( ! $time );

	    # episode and season
      my $epino = formattedCell($oWkS, $columns{'Ep No'}, $iR);
      my $seano = formattedCell($oWkS, $columns{'Ser No'}, $iR);

	    # extra info
	    my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);
	    my $year = formattedCell($oWkS, $columns{'Year'}, $iR);

      progress("BBCWW: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

      # Extra
  	  $ce->{subtitle}        = norm(formattedCell($oWkS, $columns{'Episode Title'}, $iR));
  	  $ce->{actors}          = parse_person_list(norm(formattedCell($oWkS, $columns{'CastTime'}, $iR)));
  	  $ce->{directors}       = parse_person_list(norm(formattedCell($oWkS, $columns{'Director'}, $iR)));
  	  $ce->{presenters}      = parse_person_list(norm(formattedCell($oWkS, $columns{'Presenter'}, $iR)));
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      # Remove subtitles with date in the subtitle
      if($ce->{subtitle} =~ /^(\d+)\/(\d+)\/(\d\d\d\d)$/) {
        $ce->{subtitle} = undef;
      }

      if($ce->{subtitle} =~ /^Series (\d+), Episode (\d+)$/i or $ce->{subtitle} =~ /^Episode (\d+)$/i) {
        $ce->{subtitle} = undef;
      }

      # org title
      if(defined $columns{'ORGTitle'}) {
        my $title_org = formattedCell($oWkS, $columns{'ORGTitle'}, $iR);
        $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      }

      # Remove <num>/<num> in desc
      if($ce->{description} =~ /(\d+)\/(\d+)$/i) {
        $ce->{description} =~ s/(\d+)\/(\d+)$//i;
        $ce->{description} = norm($ce->{description});
      }


      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;

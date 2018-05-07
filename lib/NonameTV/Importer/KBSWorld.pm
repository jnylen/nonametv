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

use NonameTV qw/norm ParseExcel formattedCell AddCategory AddCountry/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;
  my $chanfileid = $chd->{grabber_info};

  if( $file =~ /\.(xls|xlsx)$/i ) {
    $self->ImportXLS( $file, $chd );
  } else {
    error( "KBSWorld: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "KBSWorld: $xmltvid: Processing $file" );
  my $date;
  my $currdate = "x";
  my %columns = ();

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "KBSWorld: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "KBSWorld: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;

    # go through the programs
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Date/ );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Start time/i );
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Title/ );
            $columns{'SeaNo'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Season no/ );
            $columns{'Genre'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Genre/ );
            $columns{'EpiNo'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Episode/ );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Synop/ );


            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Date/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR));
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("KBSWorld: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      my $start = formattedCell($oWkS, $columns{'Time'}, $iR);
      next if( !$start );


      # title
      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));
      next if( !$title );

      my $desc = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));
      
      my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $start,
          description => norm($desc)
      };

      my $se_num = norm(formattedCell($oWkS, $columns{'SeaNo'}, $iR));
      my $ep_num = norm(formattedCell($oWkS, $columns{'EpiNo'}, $iR));

      # Episode info in xmltv-format
      if( (defined($ep_num) and defined($se_num)) and ($ep_num ne "" and $ep_num ne "0") and ($se_num ne "" and $se_num ne "0") )
      {
          $ce->{episode} = sprintf( "%d . %d .", $se_num-1, $ep_num-1 );
      }
      elsif( defined($ep_num) and $ep_num ne "" and $ep_num ne "0" )
      {
          $ce->{episode} = sprintf( ". %d .", $ep_num-1 );
      }

      # Genre
      my $genre = norm(formattedCell($oWkS, $columns{'Genre'}, $iR));
      if(defined($genre) and $genre ne "") {
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "KBSWorld", $genre );
        AddCategory( $ce, $program_type, $category );
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


      progress( "KBSWorld: $chd->{xmltvid}: $start - $ce->{title}" );
      $dsh->AddProgramme( $ce );
    }

    $dsh->EndBatch( 1 );

  }

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

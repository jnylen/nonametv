package NonameTV::Importer::Kanal10;

use strict;
use warnings;

=pod

Channels: Kanal10 (http://kanal10.se/), Kanal10 (http://kanal10.no)

Import data from Excel-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Encode qw/decode/;
use Data::Dumper;

use NonameTV qw/norm ParseExcel formattedCell MonthNumber normUtf8/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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

  if( $file =~ /\.xls|.xlsx|ods$/i ){
    $self->ImportXLS( $file, $chd );
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

  # Process
  progress( "Kanal10: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Kanal10: $file: Failed to parse excel" );
    return;
  }

  my $currdate = "x";

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "Kanal10: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;
    my %columns = ();

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            # Kanal 10 Norge
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program/i );
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Dato/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Klokkeslett/i );

            # Kanal 10 Sverige
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program/i );
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Datum/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Fr.n$/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Beskrivning$/i );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^(Dato|Datum)/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

        # Date
        my $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR), $file);
        next if( ! $date );

        if( $date ne $currdate ){
            progress("Kanal10: Date is $date");

            if( $currdate ne "x" ) {
                $dsh->EndBatch( 1 );
            }

            my $batch_id = $xmltvid . "_" . $date;
            $dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "00:00" );
            $currdate = $date;
        }

        # Time
        next if( ! $columns{'Time'} );
        my $time = norm(formattedCell($oWkS, $columns{'Time'}, $iR));
        next if( ! $time );

        # Title
        next if( ! $columns{'Title'} );
        my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));
        $title =~ s/\((r|p)\)//g if $title;
        next if( ! $title );

        # CE
        my $ce = {
            channel_id  => $channel_id,
            start_time  => $time,
            title       => norm($title),
        };

        # Description
        if(defined($columns{'Synopsis'})) {
            $ce->{description} = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));
        }

        progress("Kanal10: $time - $title") if $title;
        $dsh->AddProgramme( $ce ) if $title;
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo, $file ) = @_;

  #print Dumper($dinfo);

  my( $month, $day, $year, $monthname );
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}\.\d{2}\.\d{4}$/ ){ # format '11/18/2011'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)\.(\d+)\.(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2} .*$/ ){ # format '10-18-11' or '1-9-11'
    ( $day, $monthname ) = ( $dinfo =~ /^(\d{1,2}) (.*)$/ );
    $month = MonthNumber($monthname, "en");

    ( $year ) = ( $dinfo =~ /(\d\d\d\d)/ );
    if(!defined($year)) {
        $year = DateTime->now->year;
    }
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub extract_episode
{
  my $self = shift;
  my( $ce ) = @_;

  my $d = $ce->{description};
  my $t = $ce->{title};

  # Try to extract episode-information from the description.
  my( $ep, $eps, $ep2, $eps2 );
  my $episode;

  ## description
  if(defined($d)) {
    # Del 2(3)
    ( $ep, $eps ) = ($d =~ /del\s+(\d+)\((\d+)\)/i );
    $episode = sprintf( " . %d/%d . ", $ep-1, $eps )
      if defined $eps;

  	if(defined $episode and defined $eps) {
  		$ce->{description} =~ s/del\s+(\d+)\((\d+)\)//i;
  	}

    # Del 2
    ( $ep ) = ($d =~ /del\s+(\d+)/i );
    $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

    if(defined $episode and defined $ep) {
      $ce->{description} =~ s/Del\s+(\d+)//i;
    }
  }

  ## title
  if(defined($t) and !defined($episode)) {
    # Del 2(3)
    ( $ep, $eps ) = ($t =~ /del\s+(\d+)\((\d+)\)/i );
    $episode = sprintf( " . %d/%d . ", $ep-1, $eps )
      if defined $eps;

  	if(defined $episode and defined $eps) {
  		$ce->{title} =~ s/del\s+(\d+)\((\d+)\)//i;
  	}

    # Del 2
    ( $ep ) = ($t =~ /del\s+(\d+)/i );
    $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

    if(defined $episode and defined $ep) {
      $ce->{title} =~ s/del\s+(\d+)//i;
    }
  }

  if( defined( $episode ) )
  {
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
  }

  $ce->{title} = norm($ce->{title});
  $ce->{description} = norm($ce->{description});
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

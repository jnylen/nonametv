package NonameTV::Importer::Ginx;

use strict;
use warnings;


=pod

Import data from XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;

use Try::Tiny;

use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm ParseExcel formattedCell AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "CET" );
  $self->{datastorehelper} = $dsh;

  #$self->{datastore}->{augment} = 1;

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

  if( $file =~ /\.(xlsx|xls)$/i ){
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
  progress( "Ginx: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Ginx: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "Ginx: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;
    my %columns = ();
    my $currdate = "x";

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Date'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Date$/i );
            $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Start Time/i );
            $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Program Title/i );
            $columns{'Sea No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Series/i );
            $columns{'Ep No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode/i );
            $columns{'Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Comment/i );

            $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /Date$/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # date
      my $date = undef;
      my $date2 = formattedCell($oWkS, $columns{'Date'}, $iR);

      try {
        $date = ParseDate( $date2 );
        next if( ! $date );
      }
      catch {
        print("error: $_");
        next;
      };

      if( defined($date) and $date ne $currdate ){

        progress("Ginx: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      } elsif(!defined($date)) {
        next;
      }

      # time
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);


      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);

      # Desc
      my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);


      my $ce = {
        channel_id  => $channel_id,
        start_time  => $time,
        title 		=> norm($title),
        description => norm($desc),
      };

      # Episode
      my $episode = formattedCell($oWkS, $columns{'Ep No'}, $iR);

        # Try to extract episode-information from the description.
      if(($episode) and ($episode ne ""))
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

      if( defined $ce->{episode} ) {
        $ce->{program_type} = 'series';
      }

		  my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
      if( defined( $st ) )
      {
        # This program is part of a series and it has a colon in the title.
        # Assume that the colon separates the title from the subtitle.
        $ce->{title} = $t;
        $title = $t;
        $ce->{subtitle} = $st;
      }

	    progress("Ginx: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname, $month, $year );

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d+\s+\d+\s+\S+\s+\d+$/ ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\d+\s+(\d+)\s+(\S+)\s+(\d+)$/ );

  # format '2014/Jan/19'
  } elsif( $dinfo =~ /^\d+\/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\/\d+$/i ){
        ( $year, $monthname, $day ) = ( $dinfo =~ /^(\d+)\/(\S+)\/(\d+)$/ );

      # format 'Fri 30 Apr 2010'
  } elsif( $dinfo =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)-\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-(\S+)-(\d+)$/ );

  # format 'Fri 30 Apr 2010'
  } elsif( $dinfo =~ /^\S+\s*\d+\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\S+\s*(\d+)\s*(\S+)\s*(\d+)$/ );
  } elsif( $dinfo =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $monthname, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $dinfo =~ /^\d+\/\d+\/\d+$/ ) { # format '2011-07-01'
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my ($mon);
  #if(!defined($month)) {
    $mon = MonthNumber( $monthname, "en" );
  #} else {
  #  $mon = $month;
    $mon+=0; 
  #}

  my $dt = DateTime->new( year   => $year,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt->ymd();
}



1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

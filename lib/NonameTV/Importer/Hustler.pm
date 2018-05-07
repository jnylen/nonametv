package NonameTV::Importer::Hustler;

use strict;
use warnings;

=pod

Channels: HustlerTV, Blue Hustler

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;

use Data::Dumper;
use File::Temp qw/tempfile/;

use CAM::PDF;


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

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls|.xlsx$/i );
  progress( "Hustler: $xmltvid: Processing $file" );


  my %columns = ();
  my $datecolumn;
  my $date;
  my $currdate = "x";
  my( $coltime, $coltitle, $colgenre, $colduration, $coldesc, $colcast, $colprodyear ) = undef;

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Hustler: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "Hustler: Processing worksheet: $oWkS->{label}" );

    # determine which column has the
    # information about the date
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( not $datecolumn ){
        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {

          next if( not $oWkS->cell($iC, $iR) );

          if( isDate( formattedCell($oWkS, $iC, $iR) ) ){
            $datecolumn = $iC;
            last;
          }
        }
      }
    }

    progress( "Hustler: $chd->{xmltvid}: Found date information in column $datecolumn" );

    # determine which column contains
    # which information
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {

        if($oWkS->cell($iC, $iR)) {
          if( not $coltime and isTime( formattedCell($oWkS, $iC, $iR) ) ){
            $coltime = $iC;
          } elsif( not $colgenre and isGenre( formattedCell($oWkS, $iC, $iR) ) ){
            $colgenre = $iC;
          } elsif( not $colduration and isDuration( formattedCell($oWkS, $iC, $iR) ) ){
            $colduration = $iC;
          } elsif( not $coltitle and isText( formattedCell($oWkS, $iC, $iR) ) ){
            $coltitle = $iC;
          } 
            
          if( not $coldesc and $oWkS->cell($iC, $iR) =~ /^Synopsis$/i ){
             $coldesc = $iC;
          }

          if( not $colcast and $oWkS->cell($iC, $iR) =~ /^Cast$/i ){
             $colcast = $iC;
          }

          if( not $colprodyear and $oWkS->cell($iC, $iR) =~ /^Year of production$/i ){
             $colprodyear = $iC;
          }

          if( not $colprodyear and $oWkS->cell($iC, $iR) =~ /^Production Year$/i ){
             $colprodyear = $iC;
          }
        }
      }

      if( defined $coltime and defined $coltitle ){
        progress( "Hustler: $chd->{xmltvid}: Found columns" );
        last;
      }

      $coltime = undef;
      $colgenre = undef;
      $coltitle = undef;
      $colduration = undef;
    }

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( isDate( formattedCell($oWkS, $datecolumn, $iR) ) ){

        $date = ParseDate( formattedCell($oWkS, $datecolumn, $iR) );

        if( $date ne $currdate ){

          progress("Hustler: Date is $date");

          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "04:00" );
          $currdate = $date;
        }

        next;
      }

      # time - column $coltime
      if(formattedCell($oWkS, $coltime, $iR) eq "") { next; }
      my $time = ParseTime( formattedCell($oWkS, $coltime, $iR) );
      next if( ! $time );

      # title - column $coltitle
      my $title = norm(formattedCell($oWkS, $coltitle, $iR)) if( formattedCell($oWkS, $coltitle, $iR) );
      next if( ! $title );

      $title =~ s/PREMIERE -//g if $title;
      $title =~ s/PREMIERE-//g if $title;
      $title =~ s/HUSTLER TV-//g if $title;
      $title =~ s/HUSTLER TV -//g if $title;
      $title =~ s/#//g if $title;

      # duration - column $colduration
      my $duration;
      if( $colduration ){
        $duration = formattedCell($oWkS, $colduration, $iR) if( formattedCell($oWkS, $colduration, $iR) );
      }

      # genre - column $colgenre
      my $genre;
      if( $colgenre ){
        $genre = formattedCell($oWkS, $colgenre, $iR) if( formattedCell($oWkS, $colgenre, $iR) );
      }

      progress("Hustler: $xmltvid: $time - $title");


      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
        rating => 18,
      };

      # Desc
      if( $coldesc ){
        my $desc = formattedCell($oWkS, $coldesc, $iR) if( formattedCell($oWkS, $coldesc, $iR) );
        $ce->{description} = norm($desc);
      }

      # Prod year
      if( $colprodyear ) {
        my $year = formattedCell($oWkS, $colprodyear, $iR) if( formattedCell($oWkS, $colprodyear, $iR) );
        if(defined $year and $year =~ /(\d\d\d\d)/ )
        {
            $ce->{production_date} = "$1-01-01";
        }
      }

      # Cast
      if( $colcast ) {
        my $cast = formattedCell($oWkS, $colcast, $iR) if( formattedCell($oWkS, $colcast, $iR) );
        if(defined $cast and $cast !~ /Various/i )
        {
          $ce->{actors} = join(";", split(", ", $cast));
        }
      }


      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Hustler', $genre );
        AddCategory( $ce, $program_type, $category );
      } else {AddCategory( $ce, "movie", "adult" );}

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $dayname, $day, $monthname, $year );

  # the format is 'Monday, 1 July 2008'
  if( $dinfo =~ /^\S+\,\s*\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\,\s*(\d+)\s+(\S+)\s+(\d+)$/ );
  } elsif( $dinfo =~ /^\S+\s+\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $month = MonthNumber( $monthname , "en" );

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $hour, $minute ) = ( $tinfo =~ /^(\d+)\:(\d+)$/ );

  if(!$hour) { return; }

  $hour = 0 if( $hour eq 24 );

  return sprintf( "%02d:%02d", $hour, $minute );
}

sub isDate
{
  my ( $text ) = @_;

#print ">$text<\n";

  # the format is 'Monday, 1 July 2008'
  if( $text =~ /^\S+\,\s*\d+\s+\S+\s+\d+$/ ){
    return 1;
  } elsif( $text =~ /^\S+\s+\d+\s+\S+\s+\d+$/ ){
    return 1;
  }

  return 0;
}

sub isTime
{
  my ( $text ) = @_;

  # the format is '00:00'
  if( $text =~ /^\d+\:\d+$/ ){
    return 1;
  } else {
    if( $text =~ /^\d+\:\d+$/ ){
        return 1;
    }
  }

  return 0;
}

sub isGenre
{
  my ( $text ) = @_;

  # the format is 'movie|magazine'
  if( $text =~ /^(movie|magazine)$/ ){
    return 1;
  }

  return 0;
}

sub isText
{
  my ( $text ) = @_;

  # the format is whatever but not blank
  if( $text =~ /\S+/ ){
    return 1;
  }

  return 0;
}

sub isDuration
{
  my ( $text ) = @_;

  # the format is '(00:00)'
  if( $text =~ /^\(\d+\:\d+\)$/ ){
    return 1;
  }

  return 0;
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

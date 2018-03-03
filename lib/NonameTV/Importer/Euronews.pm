package NonameTV::Importer::Euronews;

use strict;
use warnings;


=pod

Import data from XLS or XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm ParseExcel formattedCell AddCategory/;
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

  $self->{datastore}->{augment} = 1;

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

  if( $file =~ /\.xls|.xlsx$/i ){
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

  # Only process .xls or .xlsx files.
  progress( "Euronews: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Euronews: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "Euronews: Processing worksheet: $oWkS->{Name}" );

	  my $foundcolumns = 0;
    my $currdate = "x";

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Programme Title/i );
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Date/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Start Time/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^EPG Synopsis/i );
            $columns{'Genre'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Theme/i );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^Date/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }


      # date
      $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("Euronews: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);


      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      $ce->{description} = formattedCell($oWkS, $columns{'Synopsis'}, $iR);

      # Genre
      my $genre = formattedCell($oWkS, $columns{'Genre'}, $iR);
      if( $genre and $genre ne "" ) {
        my($program_type, $category ) = $ds->LookupCat( 'Euronews', $genre );
        AddCategory( $ce, $program_type, $category );
      }

	    progress("Euronews: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  #print Dumper($dinfo);

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}\d{2}\d{2}$/ ){ # format   '20100422'
  	( $year, $month, $day ) = ( $dinfo =~ /^(\d{4})(\d{2})(\d{2})$/ );
  }elsif( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

package NonameTV::Importer::FuelTV;

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


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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
  progress( "FuelTV: $xmltvid: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "FuelTV: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "FuelTV: Processing worksheet: $oWkS->{label}" );

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
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Date/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^CET/i );
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Show/i );
            $columns{'Ep Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Episode Title/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Synopsis/i );
            $columns{'Ses No'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Season/i );
            $columns{'Ep No'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Episode/i );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /^Date/i ); # Only import if date is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }


      # date
      my $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("FuelTV: Date is $date");

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
      next if(! $time);


      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };
      
      my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
      if( defined( $st ) )
      {
        # This program is part of a series and it has a colon in the title.
        # Assume that the colon separates the title from the subtitle.
        $ce->{title} = norm($t);
        $ce->{subtitle} = norm($st);
      }
      
      # Desc (only works on XLS files)
      $ce->{description} = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));

      # Episode
      my $episode = formattedCell($oWkS, $columns{'Ep No'}, $iR);
      my $season = formattedCell($oWkS, $columns{'Ses No'}, $iR);
      
      # Try to extract episode-information from the description.
			if(($season) and ($season ne "")) {
				# Episode info in xmltv-format
  			if(($episode) and ($episode ne "") and ($season ne "") )
   			{
        	#$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
   			}
  
  			if( defined $ce->{episode} ) {
    			$ce->{program_type} = 'series';
				}
			}
      
	    progress("FuelTV: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;
  
#  print Dumper($dinfo);

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22' 
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

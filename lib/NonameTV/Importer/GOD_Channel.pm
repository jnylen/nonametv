package NonameTV::Importer::GOD_Channel;

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
  progress( "GOD_Channel: $chd->{xmltvid}: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "GOD_Channel: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "GOD_Channel: Processing worksheet: $oWkS->{label}" );

	  my $foundcolumns = 0;
    my %columns = ();
    my $currdate = "x";

    # Rows
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
      			$columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /Date/i );
            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /Start time/i );
            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Programme Title/i );
            $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/i );
            $columns{'Season'} = $iC if( $oWkS->cell($iC, $iR) =~ /Season number/i );
            $columns{'Episode'} = $iC if( $oWkS->cell($iC, $iR) =~ /(Episodenumber|Episode number)/i );


            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Date/i ); # Only import if season number is found
          }
        }
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date
      my $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("GOD_Channel: Date is $date");

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

      my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
      if( defined( $st ) )
      {
        # This program is part of a series and it has a colon in the title.
        # Assume that the colon separates the title from the subtitle.
        $ce->{title} = norm($t);
        $ce->{subtitle} = norm($st);
      }

      my( $t1, $p ) = ($ce->{title} =~ /(.*)\- (.*)/);
      if(defined($p)) {
        # This program has an presenter, add it.
        $ce->{title} = norm($t1);
        $ce->{presenters} = parse_person_list(norm($p));
      }

      # Desc (only works on XLS files)
    	my $desc = formattedCell($oWkS, $columns{'Synopsis'}, $iR);
    	$ce->{description} = norm($desc) if( $desc and $desc ne "WITHOUT SYNOPSIS" );

	    progress("GOD_Channel: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
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

sub ParseDate
{
  my ( $dinfo ) = @_;

  #print Dumper($dinfo);

  my( $month, $day, $year, $monthname );
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\S+-\d{2}$/ ){ # format '3-Jan-2016'
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-(\S+)-(\d+)$/ );
    $month = MonthNumber( $monthname , "en" );
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

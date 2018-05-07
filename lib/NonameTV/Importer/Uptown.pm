package NonameTV::Importer::Uptown;

use strict;
use warnings;

=pod
Importer for Uptown TV AS

Channels: Uptown Classic

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.(xlsx|xls)$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Uptown: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";
  my $oBook;

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "FOXTV: $file: Failed to parse excel" );
    return;
  }

  progress( "Uptown: $chd->{xmltvid}: Processing $file" );

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);

    progress( "Uptown: $chd->{xmltvid}: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 2 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
            $columns{'Date'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Dato\:/ );

            $columns{'Time'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Start tid\:/ );

            $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Program\:/ );
            $columns{'SubTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /^V.rk\:/ );
            $columns{'Year'} = $iC if( $oWkS->cell($iC, $iR) =~ /^Optagelse\:/ );

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Dato\:/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate( formattedCell($oWkS, $columns{'Date'}, $iR) );
      next if( ! $date );

      # Startdate
      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
           # save last day if we have it in memory
           #	FlushDayData( $channel_xmltvid, $dsh , @ces );
           $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Uptown: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      my $time = formattedCell($oWkS, $columns{'Time'}, $iR);
      next if(!$time);

      # title
      my $title = formattedCell($oWkS, $columns{'Title'}, $iR);
      next if(!$title);

      # subtitle
      my $subtitle = formattedCell($oWkS, $columns{'SubTitle'}, $iR);

      # Extra
      my $year = formattedCell($oWkS, $columns{'Year'}, $iR) if formattedCell($oWkS, $columns{'Year'}, $iR);

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $subtitle ),
        start_time => $time,
      };

      # Episode number
      my ( $epnum ) = ($ce->{title} =~ /Ep\.\s*(\d+)$/i );
      if(defined($epnum)) {
        $ce->{episode} = sprintf( ". %d .", $epnum-1 );
        $ce->{program_type} = "series";

        $ce->{title} =~ s/Ep\.\s*(\d+)$//i;
        $ce->{title} = norm($ce->{title});
      }

      progress("Uptown: $chd->{xmltvid}: $time - $ce->{title}");

      $dsh->AddProgramme( $ce );
    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  #print("text: $text\n");

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/ );
  } elsif( $text =~ /^(\d\d)-(\d\d)-(\d\d\d\d)/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d\d)-(\d\d)-(\d\d\d\d)/ );
  }

  return undef if !defined($year);
  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );

  return join( ";", grep( /\S/, @persons ) );
}

1;

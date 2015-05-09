package NonameTV::Importer::RussiaToday;

use strict;
use warnings;

=pod



=cut


use DateTime;
use Date::Parse;
use File::Slurp;
use Encode;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);

use NonameTV qw/MyGet expand_entities AddCountry AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Moscow" );
    $self->{datastorehelper} = $dsh;
  	
    return $self;
}

sub ImportContentFile
{
  my $self = shift;

  my( $file, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};


  my $cref = read_file( $file ) ;
  progress("Processing $file..");

  my $str = decode( "utf-16", $cref );
  
  my @rows = split(/\r\n|\n|\r/, $str );

  if( scalar( @rows < 2 ) )
  {
    error( "$file: No data found" );
    return 0;
  }

  my $columns = [ split( "\t", $rows[1] ) ];
  my $date = "";
  my $currdate = "x";

  # Couldnt use column name for some reason
  for ( my $i = 2; $i < scalar @rows; $i++ )
  {
    my $inrow = $self->row_to_hash($file, $rows[$i], $columns );

    $date = ParseDate($inrow->{"Date"});
    next if !defined($date);
    if ($date ne $currdate) {
      if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      progress("RT: $chd->{xmltvid}: Date is $date");
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;
    }

    my $title = norm( $inrow->{'Program Name/Main Program Title'} );
    my $start = norm( $inrow->{'Start'} );
    my $end   = norm( $inrow->{'End'} );
    my $desc  = norm( $inrow->{'Generic Program Synopsis'} );

    my $ce = {
      channel_id => $chd->{id},
      title => $title,
      description => $desc,
      start_time => $start,
      end_time => $end,
    };

    my $genre = norm( $inrow->{'Program Genre'} );
    if(defined($genre) and $genre ne "") {
    	my($program_type, $category ) = $ds->LookupCat( 'RussiaToday', $genre );
			AddCategory( $ce, $program_type, $category );
    }

    progress( "RT: $chd->{xmltvid}: $start - ".$ce->{title} );

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub row_to_hash
{
  my $self = shift;
  my( $batch_id, $row, $columns ) = @_;
  #$row =~ s/\t.$//;
 # if $(row)
  my @coldata = split( "\t", $row );
  my %res;

  
  if( scalar( @coldata ) > scalar( @{$columns} ) )
  {
    error( "$batch_id: Too many data columns " .
           scalar( @coldata ) . " > " .
           scalar( @{$columns} ) );
  }

  for( my $i=0; $i<scalar(@coldata) and $i<scalar(@{$columns}); $i++ )
  {
    my $column = $columns->[$i];

    $res{norm($column)} = norm($coldata[$i])
      if $coldata[$i] =~ /\S/; 
  }

  return \%res;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;
  #print(">$text<\n");

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return undef if !defined($year);

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

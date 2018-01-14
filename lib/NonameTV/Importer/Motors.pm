package NonameTV::Importer::Motors;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Text::CSV;
use Data::Dumper;
use File::Temp qw/tempfile/;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
use Spreadsheet::Read;
use Text::Capitalize qw/capitalize_title/;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm AddCategory MonthNumber/;
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

  if( $file =~ /\.csv$/i ){
    $self->ImportCSV( $file, $chd );
  } elsif( $file =~ /\.(xls|xlsx)$/i ){
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

  return if( $file !~ /\.(xls|xlsx)$/i );
  progress( "Motors XLS: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = undef;
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $foundcolumns = 0;
    my $i = 0;

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Motors XLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Titre du produit/i );
            $columns{'EpTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Titre de/i );
            $columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /PRESSE UK/i );
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Horaire/i );
            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date de diffusion/i );


            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date de diffusion/i ); # Only import if date is found
          }
        }
        %columns = () if( $foundcolumns eq 0 );

        next;
      }



      # date - column 0 ('Date de diffusion')
      #print Dumper(%columns);
      my $field2 = int2col($columns{'Date'}).$i;
      my $dater = $ref->[1]{$field2};
      if( $dater ){
        if( $date = ParseDate( $dater ) ){

          $dsh->EndBatch( 1 ) if defined $currdate;

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "05:00" );
          $currdate = $date;

          progress("Motors XLS: Date is $date");

          next;
        }
      }

      next if !$currdate;


      # time - column 1 ('Horaire')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = ExcelFmt("hh:mm", $oWkC->{Val} ) if( $oWkC->{Val} );
      $time = "00:00" if !defined($time);

      # Sometimes Motors somehow add 24:00:00 in the time field, that fucks the system up.
      my ( $hour , $min ) = ( $time =~ /^(\d+):(\d+)/ );
      next if !defined($hour);
      if($hour eq "24") {
      	$hour = "00";
      }

      $time = $hour.":".$min;

      # title - column 2 ('Titre du produit')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      $title =~ s/\(Live\)//g; # Dont keep live in the text
      $title = capitalize_title(lc(norm($title))); # make it prettieh



      my ( $subtitle, $description );

      # subtitle - column 3 ('Titre de l'ésode')
      $subtitle = $oWkS->{Cells}[$iR][$columns{'EpTitle'}]->Value if defined($columns{'EpTitle'}) and $oWkS->{Cells}[$iR][$columns{'EpTitle'}];

      # description - column 4 ('PRESSE UK')
      $description = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if defined($columns{'Description'}) and $oWkS->{Cells}[$iR][$columns{'Description'}];

      progress("Motors XLS: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        title => norm($title),
        start_time => $time,
      };

      $ce->{subtitle} = norm($subtitle) if $subtitle;
      $ce->{description} = norm($description) if $description;

      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $text ) = @_;
  print("text: $text\n");

  return undef if( ! $text or $text eq "" );

  # Format 'VENDREDI 27 FAVRIER   2009'
  if( $text =~ /\S+\s+\d\d\s\S+\s+\d\d\d\d/ ){

    my( $dayname, $day, $monthname, $year ) = ( $text =~ /(\S+)\s+(\d\d)\s(\S+)\s+(\d\d\d\d)/ );
#print "$dayname\n";
#print "$day\n";
#print "$monthname\n";
#print "$year\n";

    $year += 2000 if $year lt 100;

    my $month = MonthNumber( $monthname, 'fr' );
#print "$month\n";

    my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
    return $date;
  }

  return undef;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

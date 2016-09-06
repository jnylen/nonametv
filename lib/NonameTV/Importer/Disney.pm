package NonameTV::Importer::Disney;

use strict;
use warnings;

=pod

Import data from Xml-files and Excel-files delivered via e-mail in zip-files.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;
use IO::Scalar;

use Archive::Zip qw/:ERROR_CODES/;

use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel int2col);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm normUtf8 AddCategory MonthNumber FixSubtitle/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

	# use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ) {
    if( $chd->{sched_lang} eq "sv") {
        $self->ImportXML( $file, $chd ) if $file =~ /swe*.*xml$/i;
    } elsif($chd->{sched_lang} eq "da") {
        $self->ImportXML( $file, $chd ) if $file =~ /dan*.*xml$/i;
    } elsif($chd->{sched_lang} eq "fi") {
        $self->ImportXML( $file, $chd ) if $file =~ /fin*.*xml$/i;
    } elsif($chd->{sched_lang} eq "no") {
        $self->ImportXML( $file, $chd ) if $file =~ /nor*.*xml$/i;
    } elsif($chd->{sched_lang} eq "en") {
        $self->ImportXML( $file, $chd ) if $file =~ /eng*.*xml$/i and $file !~ /swe*.*xml$/i;
    }
  } elsif( $file =~ /\.xls$/i ){
    if( $chd->{sched_lang} eq "sv") {
        $self->ImportExcel( $file, $chd ) if $file =~ /swe*.*xls$/i;
    } elsif($chd->{sched_lang} eq "da") {
        $self->ImportExcel( $file, $chd ) if $file =~ /dan*.*xls$/i;
    } elsif($chd->{sched_lang} eq "fi") {
        $self->ImportExcel( $file, $chd ) if $file =~ /fin*.*xls$/i;
    } elsif($chd->{sched_lang} eq "no") {
        $self->ImportExcel( $file, $chd ) if $file =~ /nor*.*xls$/i;
    } elsif($chd->{sched_lang} eq "en") {
        $self->ImportExcel( $file, $chd ) if $file =~ /eng*.*xls$/i and $file !~ /swe*.*xls$/i;
    }
  } elsif( $file =~ /\.zip$/i ) {
  	# When ParseExcel can load a XLS file
  	# from a string Please remove this
  	# as this is too stupid.

    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @filess;

    my @members = $zip->members();
    foreach my $member (@members) {
      if($chd->{sched_lang} eq "sv") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /swe/i and $member->{fileName} =~ /\.(xls|xlsx|xml)$/i;
      } elsif($chd->{sched_lang} eq "da") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /dan/i and $member->{fileName} =~ /\.(xls|xlsx|xml)$/i;
      } elsif($chd->{sched_lang} eq "fi") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /fin/i and $member->{fileName} =~ /\.(xls|xlsx|xml)$/i;
      } elsif($chd->{sched_lang} eq "no") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /nor/i and $member->{fileName} =~ /\.(xls|xlsx|xml)$/i ;
      } elsif($chd->{sched_lang} eq "en") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /eng*.*(xls|xml)$/i and $member->{fileName} !~ /swe*.*(xls|xlsx|xml)$/i;
      }
    }

    my $numfiles = scalar( @filess );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $filess[0]";

    # file exists - could be a new file with the same filename
    # remove it.
    my $filename = '/tmp/'.$filess[0];
    if (-e $filename) {
    	unlink $filename; # remove file
    }

    my $content = $zip->contents( $filess[0] );

    open (MYFILE, '>>'.$filename);
  	print MYFILE $content;
  	close (MYFILE);

    $self->ImportExcel( $filename, $chd ) if($filename =~ /\.(xls|xlsx)$/i);
    $self->ImportXML( $filename, $chd ) if($filename =~ /\.xml$/i);
    unlink $filename; # remove file
  } else {
    error( "Disney: Unknown file format: $file" );
  }

  return;
}

sub ImportExcel
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "Disney Excel: $chd->{xmltvid}: Processing $file" );
  my $oBook;
  if ( $file =~ /\.xlsx$/i ){  $oBook = Spreadsheet::XLSX -> new ($file, $converter); } else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  my($iR, $oWkS, $oWkC);
  my %columns = ();
  my $date;
  my $currdate = "x";
  my @ces;

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    my $foundcolumns = 0;

    # Rows and columns
    my $i = 0;
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
      			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ );
            $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(NOT\) Title/ ); # Often SWE Title
			      $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(NOR\) Title/ );

            $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(ENG\) Title/ );
      			$columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /English/ );

      			$columns{'Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Production Yr/ );

            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/ );
          	$columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          	$columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season Number/ );
          	$columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Number/ );
          	$columns{'Genre'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Genre/ );
          	$columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ );

          	if($chd->{sched_lang} eq "sv") {
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(SWE\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Swedish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Swedish/ );
          	} elsif($chd->{sched_lang} eq "fi") {
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(FIN\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Finnish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Finnish/ );
          	} elsif($chd->{sched_lang} eq "no") {
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(NOR\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Norwegian/ );
              $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Norwegian/ );
          	} elsif($chd->{sched_lang} eq "da") {
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(DAN\) Title/ );
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Danish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /Danish/ );
          	} elsif($chd->{sched_lang} eq "en") {
              $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /\(ENG\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /English/ );
              $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/ ) and ( $oWkS->{Cells}[$iR][$iC]->Value =~ /English/ );
          	}

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season/ ); # Only import if season number is found
          }
        }
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # Date
      next if(!defined($columns{'Date'}));
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
	    my $date = ParseDate( $oWkC->Value );
      next if(!$date);

  	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
    		    # save last day if we have it in memory
            #FlushDayData( $xmltvid, $dsh , @ces );
    			  $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "05:00" );
        $currdate = $date;

        progress("Disney: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # program_title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = norm($oWkC->Value);
      next if( ! $title );
      $title =~ s/S(\d+)$//;
      $title = FixSubtitle(norm($title));

      $oWkC = $oWkS->{Cells}[$iR][$columns{'ORGTitle'}];
      my $title_org = norm($oWkC->Value);

      # Desc
      my $field = int2col($columns{'Synopsis'}).$i;
      my $desc = $ref->[1]{$field};

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      ## Episode
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}];
      my $episode = $oWkC->Value if( $oWkC );

      $oWkC = $oWkS->{Cells}[$iR][$columns{'Season'}];
      my $season = $oWkC->Value if( $oWkC );

      # genre (column 6)
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      my $genre = norm($oWkC->Value) if( $oWkC );

      if(defined($episode) and $episode ne "" and $episode > 0) {
        $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";
      }

      # Genre
      if( defined($genre) and $genre ne "" ){
        my ($program_type2, $category2 ) = $ds->LookupCat( 'DisneyChannel', $genre );
        AddCategory( $ce, $program_type2, $category2 );
      }

      if(defined($ce->{episode}) and $season > 0) {
        $ce->{episode} = $season-1 . $ce->{episode};
      }
      ## END

      # Desc
      $ce->{description} = normUtf8($desc) if defined($desc);
      $desc = '';

      # Find production year from description.
      if(defined($desc) and defined($ce->{description}) and $ce->{description} =~ /\((\d\d\d\d)\)/)
      {
        $ce->{description} =~ s/\((\d\d\d\d)\) //;
        $ce->{production_date} = "$1-01-01";
      }

      # Org title
      $ce->{original_title} = FixSubtitle(norm($title_org)) if $ce->{title} ne norm($title_org) and norm($title_org) ne "";

      # Production Year
      if(defined $columns{'Year'}) {
          $oWkC = $oWkS->{Cells}[$iR][$columns{'Year'}];
          my $year = $oWkC->Value if( $oWkC );

          if(defined $year and $year =~ /(\d\d\d\d)/ )
          {
              $ce->{production_date} = "$1-01-01";
          }
      }

      progress("$time - $title");
      $dsh->AddProgramme( $ce );
    }

  }

  #FlushDayData( $xmltvid, $dsh , @ces );
  $dsh->EndBatch( 1 );
  return;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{4})$/i );

  # format '2011-05-16'
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );
  }

  return undef if !defined($year);

  $year += 2000 if $year < 100;

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    time_zone => "Europe/Stockholm"
  );

	return $dt->ymd("-");
}

sub ParseTime {
  my( $text2 ) = @_;

#print "ParseTime: >$text2<\n";

  my( $hour , $min, $secs );

  if( $text2 =~ /^\d+:\d+:\d+$/ ){
    ( $hour , $min, $secs ) = ( $text2 =~ /^(\d+):(\d+):(\d+)$/ );
  }elsif( $text2 =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text2 =~ /^(\d+):(\d+)$/ );
  }

  if($hour >= 24) {
  	$hour = $hour-24;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

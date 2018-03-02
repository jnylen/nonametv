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
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;
use IO::Scalar;

use Archive::Zip qw/:ERROR_CODES/;


use NonameTV qw/norm ParseExcel formattedCell AddCategory MonthNumber FixSubtitle/;
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
  } elsif( $file =~ /\.(xls|xlsx)$/i ){
    if( $chd->{sched_lang} eq "sv") {
        $self->ImportExcel( $file, $chd ) if $file =~ /swe/i and $file =~ /\.(xls|xlsx)$/i;
    } elsif($chd->{sched_lang} eq "da") {
        $self->ImportExcel( $file, $chd ) if $file =~ /(dan|den)/i and $file =~ /\.(xls|xlsx)$/i;
    } elsif($chd->{sched_lang} eq "fi") {
        $self->ImportExcel( $file, $chd ) if $file =~ /fin/i and $file =~ /\.(xls|xlsx)$/i;
    } elsif($chd->{sched_lang} eq "no") {
        $self->ImportExcel( $file, $chd ) if $file =~ /nor/i and $file =~ /\.(xls|xlsx)$/i;
    } elsif($chd->{sched_lang} eq "en") {
        $self->ImportExcel( $file, $chd ) if $file =~ /eng/i and $file =~ /\.(xls|xlsx)$/i;
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
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /swe/i and $member->{fileName} =~ /\.(xls|xlsx)$/i;
      } elsif($chd->{sched_lang} eq "da") {
        if($chd->{xmltvid} eq "disneychannel.dk") {
          push( @filess, $member->{fileName} ) if $member->{fileName} =~ /(dan|den)/i and $member->{fileName} =~ /2959/i and $member->{fileName} =~ /\.(xls|xlsx)$/i;
        } else {
          push( @filess, $member->{fileName} ) if $member->{fileName} =~ /(dan|den)/i and $member->{fileName} =~ /\.(xls|xlsx)$/i;
        }
      } elsif($chd->{sched_lang} eq "fi") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /fin/i and $member->{fileName} =~ /\.(xls|xlsx)$/i;
      } elsif($chd->{sched_lang} eq "no") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /nor/i and $member->{fileName} =~ /\.(xls|xlsx)$/i ;
      } elsif($chd->{sched_lang} eq "en") {
        push( @filess, $member->{fileName} ) if $member->{fileName} =~ /eng/i and $member->{fileName} =~ /\.(xls|xlsx)$/i ;
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
    #$self->ImportXML( $filename, $chd ) if($filename =~ /\.xml$/i);
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

  # Process
  progress( "Disney: $xmltvid: Processing $file" );

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "Disney: $file: Failed to parse excel" );
    return;
  }

  my $currdate = "x";

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "Disney: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;
    my $batch_id;
    my %columns = ();

    # Rows
    #print Dumper($oWkS);
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      # Columns
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          # Does the cell exist?
          if($oWkS->cell($iC, $iR)) {
            $columns{'Title'} = $iC    if( $oWkS->cell($iC, $iR) =~ /Title/ );
            $columns{'Title'} = $iC    if( $oWkS->cell($iC, $iR) =~ /\(NOT\) Title/ ); # Often SWE Title
			      $columns{'Title'} = $iC    if( $oWkS->cell($iC, $iR) =~ /\(NOR\) Title/ );

            $columns{'ORGTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(ENG\) Title/ );
      		  $columns{'ORGTitle'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /English/ );

            $columns{'Year'} = $iC     if( $oWkS->cell($iC, $iR) =~ /Production Yr/ );

            $columns{'Time'} = $iC     if( $oWkS->cell($iC, $iR) =~ /Time/ );
          	$columns{'Date'} = $iC     if( $oWkS->cell($iC, $iR) =~ /Date/ );
          	$columns{'Season'} = $iC   if( $oWkS->cell($iC, $iR) =~ /Season Number/i );
          	$columns{'Episode'} = $iC  if( $oWkS->cell($iC, $iR) =~ /Episode Number/i );
          	$columns{'Genre'} = $iC    if( $oWkS->cell($iC, $iR) =~ /^Genre/ );
          	$columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ );

            if($chd->{sched_lang} eq "sv") {
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(SWE\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /Swedish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ ) and ( $oWkS->cell($iC, $iR) =~ /Swedish/ );
          	} elsif($chd->{sched_lang} eq "fi") {
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(FIN\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /Finnish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ ) and ( $oWkS->cell($iC, $iR) =~ /Finnish/ );
          	} elsif($chd->{sched_lang} eq "no") {
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(NOR\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /Norwegian/ );
              $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ ) and ( $oWkS->cell($iC, $iR) =~ /Norwegian/ );
          	} elsif($chd->{sched_lang} eq "da") {
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(DAN\) Title/ );
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /Danish/ );
              $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ ) and ( $oWkS->cell($iC, $iR) =~ /Danish/ );
          	} elsif($chd->{sched_lang} eq "en") {
              $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /\(ENG\) Title/ );
          	  $columns{'Title'} = $iC if( $oWkS->cell($iC, $iR) =~ /Title/ ) and ( $oWkS->cell($iC, $iR) =~ /English/ );
              $columns{'Synopsis'} = $iC if( $oWkS->cell($iC, $iR) =~ /Synopsis/ ) and ( $oWkS->cell($iC, $iR) =~ /English/ );
          	}

            $foundcolumns = 1 if( $oWkS->cell($iC, $iR) =~ /Season/ ); # Only import if season number is found
          }
        }

        %columns = () if( $foundcolumns eq 0 );
        next;
      }

      # Date
      my $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR), $file);
      next if( ! $date );

      if( $date ne $currdate ){
        progress("Disney: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # Time
      next if( ! $columns{'Time'} );
      my $time = ParseTime(norm(formattedCell($oWkS, $columns{'Time'}, $iR)));
      next if( ! $time );

      # Title
      next if( ! $columns{'Title'} );
      my $title = norm(formattedCell($oWkS, $columns{'Title'}, $iR));
      next if( ! $title );
      $title =~ s/S(\d+)$//;
      $title = FixSubtitle($title);

      # ORGTitle
      my $title_org;
      if(defined($columns{'ORGTitle'})) {
        $title_org = norm(formattedCell($oWkS, $columns{'ORGTitle'}, $iR));
      }

      # CE
      my $ce = {
        channel_id  => $channel_id,
        start_time  => $time,
        title       => norm($title),
      };

      # Episode & Season
      my($episode, $season);
      if(defined($columns{'Episode'})) {
        $episode = norm(formattedCell($oWkS, $columns{'Episode'}, $iR));
      }
      if(defined($columns{'Season'})) {
        $season = norm(formattedCell($oWkS, $columns{'Season'}, $iR));
      }

      if(defined($episode) and $episode ne "" and $episode > 0) {
        $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";
      }

      if(defined($ce->{episode}) and defined($season) and norm($season) ne "" and $season > 0) {
        $ce->{episode} = $season-1 . $ce->{episode};
      }

      # Genre
      my($genre);
      if(defined($columns{'Genre'})) {
        $genre = norm(formattedCell($oWkS, $columns{'Genre'}, $iR));

        # Add to CE
        if( defined($genre) and $genre ne "" ){
            my ($program_type2, $category2 ) = $ds->LookupCat( 'DisneyChannel', $genre );
            AddCategory( $ce, $program_type2, $category2 );
        }
      }

      # Description
      my($desc);
      if(defined($columns{'Synopsis'})) {
        $ce->{description} = norm(formattedCell($oWkS, $columns{'Synopsis'}, $iR));

        # Find production year from description.
        if(defined($ce->{description}) and $ce->{description} =~ /\((\d\d\d\d)\)/)
        {
            $ce->{description} =~ s/\((\d\d\d\d)\) //;
            $ce->{production_date} = "$1-01-01";
        }
      }

      # ORG. Title
      if(defined($title_org)) {
        $ce->{original_title} = FixSubtitle(norm($title_org)) if $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      }

      # Production Year
      my($year);
      if(defined($columns{'Year'})) {
        $year = norm(formattedCell($oWkS, $columns{'Year'}, $iR));

        if(defined $year and $year =~ /(\d\d\d\d)/ )
        {
            $ce->{production_date} = "$1-01-01";
        }
      }

      progress("$batch_id: $time - $title");
      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );
  return;
}

sub ParseDate {
  my ( $text ) = @_;

  return undef if !defined($text);

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

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text2 ) = @_;

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

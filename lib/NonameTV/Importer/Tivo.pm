package NonameTV::Importer::Tivo;

use strict;
use warnings;

=pod

Import data that is provided by Tivo for channels.

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;

use XML::LibXML;
use IO::Scalar;
use Try::Tiny;

## TEMP
use Spreadsheet::ParseExcel;
##

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd->{id}, $chd->{xmltvid} );
  } elsif( $file =~ /\.zip$/i ) {
  	# When ParseExcel can load a XLS file
  	# from a string Please remove this
  	# as this is too stupid.

    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @files;

    my @members = $zip->members();
    foreach my $member (@members) {
      push( @files, $member->{fileName} ) if $member->{fileName} =~ /\.xml$/i;
    }

    my $numfiles = scalar( @files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $files[0]";

    # file exists - could be a new file with the same filename
    # remove it.
    my $filename = '/tmp/'.$files[0];
    if (-e $filename) {
    	unlink $filename; # remove file
    }

    my $content = $zip->contents( $files[0] );

    open (MYFILE, '>>'.$filename);
  	print MYFILE $content;
  	close (MYFILE);

    $self->ImportXML( $filename, $chd );
    unlink $filename; # remove file
  } else {
    error( "Tivo: Unknown file format: $file" );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "Tivo: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Tivo: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( ".//listing" );

  if( $rows->size() == 0 ) {
    error( "Tivo: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  my $timezone = $doc->findvalue( '//channel/@timeZone' );

  foreach my $row ($rows->get_nodelist) {
    my $title   = $row->findvalue( './/title' );
    my $serdesc = $row->findvalue( './/synopsis' );
    my $epdesc  = $row->findvalue( './/episodeSynopsis' );
    my $desc    = $epdesc || $serdesc;

    my ($start);
    try {
      $start = $self->create_dt( $row->findvalue( './/broadcastDate' ), $timezone );
    }
    catch { print("error: $_"); next; };

    my $date = $start->ymd("-");

    if($date ne $currdate ) {
      if( $currdate ne "x" ) {
           $dsh->EndBatch( 1 );
      }

      my $batchid = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batchid , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("Tivo: Date is: $date");
    }

    my $ce = {
      channel_id => $chd->{id},
      title => norm($title),
      start_time => $start->hms(":"),
      description => norm($desc),
    };

    # Extra
    my $programtype = $row->findvalue( './/programType' );
    my $genre       = $row->findvalue( './/genres' );
    my $prodyear    = $row->findvalue( './/yearOfProduction' );
    my $audio       = $row->findvalue( './/audioType' );
    my $sixteenNine = $row->findvalue( './/sixteenNine' );
    my $hd          = $row->findvalue( './/HD' );
    my @directors   = split(", ", $row->findvalue( './/directors' ));
    my @actors      = split(", ", $row->findvalue( './/actors' ));
    my $episode      = $row->findvalue( './/episodeNb' );
    my $of_episode   = $row->findvalue( './/episodeCount' );

    # Subtitle
    $ce->{subtitle} = norm($row->findvalue( './/episodeTitle' )) if defined $row->findvalue( './/episodeTitle' ) and $row->findvalue( './/episodeTitle' ) ne "";
    $ce->{subtitle} =~ s|(.*), the$|The $1|i if defined $ce->{subtitle};
    $ce->{subtitle} =~ s|(.*), a$|A $1|i if defined $ce->{subtitle};
    $ce->{subtitle} =~ s|(.*),the$|The $1|i if defined $ce->{subtitle};

    my ($season, $episode2, $newsub, $newtitle);
    if(defined($ce->{subtitle})) {
      if( ( $season, $episode2, $newsub ) = ($ce->{subtitle} =~ m|^S.son (\d+) - Episode (\d+)\: (.*?)$| ) ){
        $ce->{episode} = ($season - 1) . ' . ' . ($episode2 - 1) . ' .';
        $ce->{subtitle} = norm($newsub);
      } elsif( ( $season, $episode2, $newsub ) = ($ce->{subtitle} =~ m|^Sesong (\d+) - Episode (\d+)\: (.*?)$| ) ) {
        $ce->{episode} = ($season - 1) . ' . ' . ($episode2 - 1) . ' .';
        $ce->{subtitle} = norm($newsub);
      } elsif( ( $season, $episode2, $newsub ) = ($ce->{subtitle} =~ m|^S.song (\d+) - Episod (\d+)\: (.*?)$| ) ) {
        $ce->{episode} = ($season - 1) . ' . ' . ($episode2 - 1) . ' .';
        $ce->{subtitle} = norm($newsub);
      }
    }

    # Season
    if( ( $newtitle, $season ) = ($ce->{title} =~ m|^(.*?) - Season (\d+)$| )  ) {
      $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
      $ce->{title} = norm($newtitle);
    }

    $ce->{title} =~ s|(.*), the$|The $1|i;
    $ce->{title} =~ s|(.*), a$|A $1|i;
    $ce->{title} =~ s|(.*),the$|The $1|i;


    # Episodenum
    if(!defined($ce->{episode}) and ($episode ne "") and ( $of_episode ne "") )
    {
      $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
    }

    # Program type
    my( $pty, $cat );
    if(defined($programtype) and $programtype and $programtype ne "") {
        ( $pty, $cat ) = $ds->LookupCat( 'Tivo_type', $programtype );
        AddCategory( $ce, $pty, $cat );
    }

    if(defined($genre) and $genre and $genre ne "") {
      my @genres = split(",", $genre);
      my @cats;
      foreach my $node ( @genres ) {
        my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tivo_genres", $node );
        push @cats, $categ if defined $categ;
      }
      $cat = join "/", @cats;
      AddCategory( $ce, $pty, $cat );
    }

    $ce->{stereo} = "mono" if $audio eq "mono";
    $ce->{stereo} = "stereo" if $audio eq "stereo";
    $ce->{stereo} = "dolby digital" if $audio eq "dolby E5.1";
    $ce->{aspect} = "16:9" if $sixteenNine eq "true";
    $ce->{aspect} = "4:3"  if $sixteenNine eq "false" or $sixteenNine eq "";
    $ce->{production_date} = "$prodyear-01-01" if(defined($prodyear) and $prodyear ne "");
    $ce->{actors} = join(";", @actors) if(@actors and scalar( @actors ) > 0 );
    $ce->{directors} = join(";", @directors) if(@directors and scalar( @directors ) > 0 );
    $ce->{quality} = "HDTV" if $hd eq "true";

    progress( "Tivo: $chd->{xmltvid}: $start - $ce->{title}" );
    $dsh->AddProgramme( $ce );

  } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
  my $self = shift;
  my ($timestamp, $timezone) = @_;

  if( $timestamp ){
    my ($year, $month, $day, $hour, $minute) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/);
    if( !defined( $year )|| !defined( $hour ) || ($month < 1) ){
      w( "could not parse timestamp: $timestamp" );
      return undef;
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => $timezone
    );

    $dt->set_time_zone( 'UTC' );

    return( $dt );
  } else {
    return undef;
  }
}

## TEMP XLS THINGS FOR CNN UNTIL TIVO TAKES OVER
sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );

  progress( "Turner XLS: $xmltvid: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  if( not defined( $oBook ) ) {
    error( "Turner XLS: Failed to parse xls" );
    return;
  }

  my $date;
  my $currdate = "x";
  my @ces = ();

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++){

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /Header/ ){
      progress("Turner XLS: $xmltvid: skipping worksheet '$oWkS->{Name}'");
      next;
    }
    progress("Turner XLS: $xmltvid: processing worksheet '$oWkS->{Name}'");

    # the time is in the column 0
    # the columns from 1 to 7 are each for one day
    for(my $iC = 1 ; $iC <= 7  ; $iC++) {

      # get the date from row 1
      my $oWkC = $oWkS->{Cells}[1][$iC];
      next if( ! $oWkC );
      $date = ParseDateXLS( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          # save last day if we have it in memory
          FlushDayData( $xmltvid, $dsh , @ces );
          $dsh->EndBatch( 1 );
          @ces = ();
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Turner XLS: $xmltvid: Date is: $date");
      }

      my $time;
      my $title = "x";
      my $description;
      my $title_org;

      # browse through the shows
      # starting at row 2
      for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++){

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;

        if( isTimeAndTitle( $text ) ){

          # check if we have something
          # in the memory already
          if( $title ne "x" ){

      		  # Remove (UU) and so on
      			$title =~ s/\(.*\)//g;
      			$title =~ s/^NIEUW//i;
      			$title =~ s/\- Season (\d+)//i;
      			$title =~ s/^://i;

            my $ce = {
              channel_id   => $channel_id,
              start_time => $time,
              title => norm($title),
            };

            $ce->{description} = $description if $description;
            $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

            push( @ces , $ce );
            $description = "";
          }

          ( $time, $title ) = ParseTimeAndTitle( $text );
        } else {
          $description .= $text;
        }

      } # next row

    } # next column
  } # next sheet

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );

  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

      	# Get year from description
      	if(defined($element->{description})) {
      		my( $year ) = ( $element->{description} =~ /^(\d\d\d\d),/ );
      		if($year) {
      			$element->{production_date} = $year."-01-01";
      		}

      		# Credits
      		if( $element->{description} =~ /Dir:/ ) {
      			my ( $dirs, $actors ) = ( $element->{description} =~ /Dir:\s+([A-Z].+?),\s+Act:\s+([A-Z].+?),\s+Sub/ );
						# Put them into the array
						if(defined($dirs) and $dirs ne "") {
							#print Dumper($dirs, $actors);
							my @directors = split( /\s*,\s*/, $dirs );
							$element->{directors} = join( ";", grep( /\S/, @directors ) );
						}
						if(defined($actors) and $actors ne "") {
							my @actors = split( /\s*,\s*/, $actors );
							$element->{actors} = join( ";", grep( /\S/, @actors ) );
						}

						# Movies
						$element->{program_type} = "movie";
      		}
      	}

        progress("Turner: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub ParseDateXLS {
  my( $text ) = @_;

#print "ParseDateXLS: >$text<\n";

  return undef if ( ! $text );

  my( $month, $day, $year );

  if( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/ ){ # format '2010-04-26'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^(\d+)-(\d+)-(\d+)$/ ){ # format '8-1-08'
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  $year += 2000 if( $year < 100 );

  return sprintf( '%04d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format 'UK 19.35 / CET 20.35 / CAT 20.35 And the title is here'
  # or
  # UK Time 05.30 / CET 06.30 / CAT 06.30 Looney Tunes
  if( $text =~ /^UK\s+\S*\s*\d+\.\d+\s+\/\s+CET\s+\d+\.\d+\s+\/\s+CAT\s+\d+\.\d+\s+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^UK\s+\S*\s*\d+\.\d+\s+\/\s+CET\s+(\d+)\.(\d+)\s+\/\s+CAT\s+\d+\.\d+\s+(.*)/ );

  return( $hour . ":" . $min , $title );
}

sub isTimeAndTitle {
  my ( $text ) = @_;

  # format '09:10 The Addams Family'
  if( $text =~ /^\d{2}:\d{2}\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseTimeAndTitle {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^(\d{2}):(\d{2})\s+(.*)$/ );

  return( $hour . ":" . $min , $title );
}

## END


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

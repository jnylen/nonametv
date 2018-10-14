package NonameTV::Importer::FOXTV;

use strict;
use warnings;

=pod

Import data from FOX

Channels: FOX (SWEDEN), FOX (NORWAY), Nat Geo Scandinavia & Iceland

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;

use NonameTV qw/norm ParseExcel formattedCell AddCategory AddCountry/;
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

  $self->{Timezone} = "Europe/Stockholm" unless defined $self->{Timezone};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, $self->{Timezone} );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;
  my $chanfileid = $chd->{grabber_info};

  if( $file =~ /\.(xls|xlsx)$/i ) {
    $self->ImportXLS( $file, $chd );
  } else {
    error( "FOXTV: Unknown file format: $file" );
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
  progress( "FOXTV: $xmltvid: Processing $file" );
  my $date;
  my $currdate = "x";
  my %columns = ();

  my $doc = ParseExcel($file);

  if( not defined( $doc ) ) {
    error( "FOXTV: $file: Failed to parse excel" );
    return;
  }

  # main loop
  for(my $iSheet=1; $iSheet <= $doc->[0]->{sheets} ; $iSheet++) {
    my $oWkS = $doc->sheet($iSheet);
    progress( "FOXTV: Processing worksheet: $oWkS->{label}" );

    my $foundcolumns = 0;

    # go through the programs
    for(my $iR = 1 ; defined $oWkS->{maxrow} && $iR <= $oWkS->{maxrow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = 1 ; defined $oWkS->{maxcol} && $iC <= $oWkS->{maxcol} ; $iC++) {
          if( $oWkS->cell($iC, $iR) ){
            $columns{'Date'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Date$/i );

            $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Start Time$/i );

            $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Program Title$/i );
            $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name English$/i );

            $columns{'ORGTitle'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Original Title$/i );
            $columns{'ORGTitle'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Original Program Title$/i );

            $columns{'Ser No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Season Number/i );
            $columns{'Ser Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Season Synopsis/i );
            $columns{'Ser SynopsisORG'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Original Season Synopsis/i );

            $columns{'Ep No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Episode Number/i );
            $columns{'Ep TitleORG'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Original Episode Title/i );
            $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Synopsis/i );
            $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Synopsis English$/i );
            $columns{'Ep SynopsisORG'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Original Episode Synopsis/i );
            $columns{'Eps'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Number of episodes in the Season/i );

            $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Longline/i );

            $columns{'Country'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Production Country/i );
            $columns{'Country'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Country of origin/i );
            $columns{'Year'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Year Of Release/i );
            $columns{'Actors'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Actors/i );
            $columns{'Directors'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Director\/s/i );

            $columns{'HD'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /High Definition/i );
            $columns{'169'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /16:9 Format/i );
            $columns{'Premiere'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Premiere/i );
            $columns{'Repeat'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Repeat/i );

            if($chd->{xmltvid} eq "natgeo.lt" or $chd->{xmltvid} eq "natgeo.lv") {
              $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Baltics Time/i );
              $columns{'Ep Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Title English/i );
              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /Baltics Time/i );
            } elsif($chd->{sched_lang} eq "et") {
              $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Baltics Time/i );
              $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Estonian/i );
              $columns{'Ep Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Title/i and norm($oWkS->cell($iC, $iR)) =~ /Estonian/i );
              $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Synopsis/i and norm($oWkS->cell($iC, $iR)) =~ /Estonian/i );
              $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Genre$/i );

              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Estonian/i );
            } elsif($chd->{sched_lang} eq "lv") {
              $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Baltics Time/i );
              $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Latvian/i );
              $columns{'Ep Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Title/i and norm($oWkS->cell($iC, $iR)) =~ /Latvian/i );
              $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Synopsis/i and norm($oWkS->cell($iC, $iR)) =~ /Latvian/i );
              $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Genre$/i );

              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Latvian/i );
            } elsif($chd->{sched_lang} eq "lt") {
              $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /Baltics Time/i );
              $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Lithuanian/i );
              $columns{'Ep Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Title/i and norm($oWkS->cell($iC, $iR)) =~ /Lithuanian/i );
              $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Synopsis/i and norm($oWkS->cell($iC, $iR)) =~ /Lithuanian/i );
              $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Genre$/i );

              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /^Series Name/i and norm($oWkS->cell($iC, $iR)) =~ /Lithuanian/i );
            } elsif($chd->{sched_lang} eq "sr" or $chd->{sched_lang} eq "hr" or $chd->{sched_lang} eq "sl") {
              $columns{'Date'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Dates$/i );
              $columns{'Time'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Time$/i );
              $columns{'Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Local Title$/i );
              $columns{'ORGTitle'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Original Title Series$/i );
              $columns{'Ser No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Season$/i );
              $columns{'Ep No'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Ep No$/i );
              $columns{'Ep Synopsis'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Synopsis$/i );
              $columns{'Year'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Year$/i );
              $columns{'Genre'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Genre$/i );

              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /^Local Title$/i );
            } else {
              $columns{'Ep Title'} = $iC if( norm($oWkS->cell($iC, $iR)) =~ /^Episode Title/i );
              $foundcolumns = 1 if( norm($oWkS->cell($iC, $iR)) =~ /Date/ );
            }
            
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      $date = ParseDate(formattedCell($oWkS, $columns{'Date'}, $iR));
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
        progress("FOXTV: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      my $start = formattedCell($oWkS, $columns{'Time'}, $iR);
      #next if( !$start );


      # title
      my $title_lang = norm(formattedCell($oWkS, $columns{'Title'}, $iR)) if norm(formattedCell($oWkS, $columns{'Title'}, $iR)) ne "-";

      my $title_org = norm(formattedCell($oWkS, $columns{'ORGTitle'}, $iR) ) if defined(formattedCell($oWkS, $columns{'ORGTitle'}, $iR));

      my $title = $title_lang || $title_org;


      my $hd = norm(formattedCell($oWkS, $columns{'HD'}, $iR) ) if defined(formattedCell($oWkS, $columns{'HD'}, $iR));
      my $ws = norm(formattedCell($oWkS, $columns{'169'}, $iR) ) if defined(formattedCell($oWkS, $columns{'169'}, $iR));
      my $yr = norm(formattedCell($oWkS, $columns{'Year'}, $iR)) if defined(formattedCell($oWkS, $columns{'Year'}, $iR));

      my $ep_desc = formattedCell($oWkS, $columns{'Ep Synopsis'}, $iR);
      my $se_desc = formattedCell($oWkS, $columns{'Ser Synopsis'}, $iR);

      my $subtitle = norm(formattedCell($oWkS, $columns{'Ep Title'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Ep Title'}, $iR)) and norm(formattedCell($oWkS, $columns{'Ep Title'}, $iR) ) ne "-";
      my $ep_num   = norm(formattedCell($oWkS, $columns{'Ep No'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Ep No'}, $iR));
      my $se_num   = norm(formattedCell($oWkS, $columns{'Ser No'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Ser No'}, $iR));
      my $of_num   = norm(formattedCell($oWkS, $columns{'Eps'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Eps'}, $iR));
      my $genre    = norm(formattedCell($oWkS, $columns{'Genre'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Genre'}, $iR));
      my $prodcountry = norm(formattedCell($oWkS, $columns{'Country'}, $iR) ) if defined(formattedCell($oWkS, $columns{'Country'}, $iR));
      my $actors      = formattedCell($oWkS, $columns{'Actors'}, $iR) if defined(formattedCell($oWkS, $columns{'Actors'}, $iR));
      $actors =~ s/^, //g;
      $actors =~ s/, /;/g;
      $actors =~ s/-$//g;
      $actors =~ s/;$//g;
      $actors =~ s/,$//g;
      my $directors = formattedCell($oWkS, $columns{'Directors'}, $iR) if defined(formattedCell($oWkS, $columns{'Directors'}, $iR));
      $directors =~ s/^, //g;
      $directors =~ s/, /;/g;
      $directors =~ s/-$//g;
      $directors =~ s/;$//g;
      $directors =~ s/,$//g;

      my $desc;
      $desc = $ep_desc if(defined($ep_desc));
      $desc = $se_desc if !defined($ep_desc) and defined($se_desc) or norm($ep_desc) eq "" or norm($ep_desc) eq "-" or norm($ep_desc) eq "1";
      $desc = "" if $desc eq "" or $desc eq "-" or $desc eq "\x{2d}" or $desc eq "1";

      my $premiere = norm(formattedCell($oWkS, $columns{'Premiere'}, $iR) );

      my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $start,
          description => norm($desc)
      };

      my $extra = {};
      $extra->{qualifiers} = [];

      if( defined( $yr ) and ($yr =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      # Aspect
      if(defined($ws) and $ws eq "Yes")
      {
        $ce->{aspect} = "16:9";
      } else {
        $ce->{aspect} = "4:3";
      }

      # HDTV & Actors
      $ce->{quality} = 'HDTV' if (defined($hd) and $hd eq 'Yes');
      $ce->{actors} = norm($actors) if($actors ne "" and $actors ne "null");
      $ce->{directors} = norm($directors) if($directors ne "" and $directors ne "null");
      $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "" and $subtitle ne "null";

      # Episode info in xmltv-format
      if( (defined($ep_num) and defined($se_num) and defined($of_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "" and $ep_num ne "0") and ( $of_num ne "\x{2d}" and $of_num ne "" and $of_num ne "0") and ( $se_num ne "\x{2d}" and $se_num ne "" and $se_num ne "0") )
      {
          $ce->{episode} = sprintf( "%d . %d/%d .", $se_num-1, $ep_num-1, $of_num );
      }
      elsif( (defined($ep_num) and defined($of_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "" and $ep_num ne "0") and ( $of_num ne "\x{2d}" and $of_num ne "" and $of_num ne "0") )
      {
          $ce->{episode} = sprintf( ". %d/%d .", $ep_num-1, $of_num );
      }
      elsif( (defined($ep_num) and defined($se_num)) and ($ep_num ne "\x{2d}" and $ep_num ne "" and $ep_num ne "0") and ( $se_num ne "\x{2d}" and $se_num ne "" and $se_num ne "0") )
      {
          $ce->{episode} = sprintf( "%d . %d .", $se_num-1, $ep_num-1 );
      }
      elsif( defined($ep_num) and $ep_num ne "\x{2d}" and $ep_num ne "" and $ep_num ne "0" )
      {
          $ce->{episode} = sprintf( ". %d .", $ep_num-1 );
      }

      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "FOXTV", $genre );
      AddCategory( $ce, $program_type, $category );

      if($prodcountry ne "-" and $prodcountry ne "\x{2d}") {
        my ( $country ) = $self->{datastore}->LookupCountry( "FOXTV", $prodcountry );
        AddCountry( $ce, $country );
      }

      # Original title
      $title_org =~ s/(Series |Y)(\d+)$//i;
      $ce->{title} =~ s/$se_num//i if defined $se_num;
      $ce->{title} = norm($ce->{title});
      $title_org =~ s/$se_num//i if defined $se_num;
      if(defined($title_org) and norm($title_org) =~ /, The$/i)  {
          $title_org =~ s/, The//i;
          $title_org = "The ".norm($title_org);
      }
      $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

      if( $premiere eq "Premiere" )
      {
        $ce->{new} = "1";
        push @{$extra->{qualifiers}}, "new";
      }
      else
      {
        $ce->{new} = "0";
        push @{$extra->{qualifiers}}, "repeat";
      }

      $ce->{extra} = $extra;

      progress( "FOXTV: $chd->{xmltvid}: $start - $title" );
      $dsh->AddProgramme( $ce );
    }

    $dsh->EndBatch( 1 );

  }

}

sub ParseDate {
  my( $text ) = @_;

  my( $month, $day, $year );

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d\d\d\d$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d\d\d\d)$/ );
  }

  if(not defined($year)) {
    return undef;
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

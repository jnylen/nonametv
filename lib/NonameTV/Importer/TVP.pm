package NonameTV::Importer::TVP;

use strict;
use warnings;

=pod

Importer for TVP
Channels: TVPolonia, TVP, TVP2, TVPKultura, more.

=cut

use utf8;

use NonameTV qw/AddCategory ParseXml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f progress/;
use Roman;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore} );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );


 	my( $folder, $endtag ) = split( /:/, $chd->{grabber_info} );
 
  my $url = sprintf( "%s%sxml_OMI/m%04d%02d%02d_%s.xml",
                     $self->{UrlRoot}, $folder, 
                     $year, $month, $day, $endtag );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $doc = ParseXml ($cref);
  
  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $ns = $doc->find ('//APCData');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my( $date ) = ($batch_id =~ /_(.*)$/);
  
  $dsh->StartDate( $date , '00:00' );


	my $ns2 = $doc->find ('//prrecord');
  foreach my $programme ($ns2->get_nodelist) {
  	# Time
    my ($time) = ($programme->findvalue ('./START') =~ m|(\d+\:\d+)|);
    if( !defined( $time ) ){
      w( 'programme without start time!' );
    }else{
    	$time = ParseTime($time);
    	
    	
      # Title
      my $title      = norm($programme->findvalue ('./RTITEL'));
      my $title_org  = norm($programme->findvalue ('./ORIG'));
      my $title_full = norm($programme->findvalue ('TITEL'));
      if(!$title) {
      	$title = $title_full
      }

      my ($year) = $programme->findvalue ('./JAHR');
      my ($desc) = $programme->findvalue ('./EPG');

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title
      };

      # Desc
      if(defined $desc) {
        $ce->{description} = norm($desc);
      }

	  # Episode
	  my ($ep) = $programme->findvalue ('./TEIL');
			
			# Use year as season if found
  		if( ($ep) and ($year) )
   		{
            $ce->{episode} = sprintf( "%d . %d .", $year-1, $ep-1 );
   		} elsif(($ep) and (!$year)) {
   			$ce->{episode} = sprintf( ". %d .", $ep-1 );
   		}
			

		# Stereo (It's actually in the correct form)
		#my ($stereo) = $programme->findvalue ('./STDDZWIEKU');
		#$ce->{stereo} = norm($stereo) if $stereo;

		# Aspect (It's actually in the correct form)
		my ($aspect) = $programme->findvalue ('./FORMATOBRAZU');
		$ce->{aspect} = norm($aspect) if $aspect;

		# Actors (It's actually in the correct form)
		my ($actors) = $programme->findvalue ('./WYKONAWCY');
		$ce->{actors} = parse_person_list(norm($actors)) if $actors;

		# Directors (It's actually in the correct form)
		my ($directors) = $programme->findvalue ('./REGIE');
		$ce->{directors} = parse_person_list(norm($directors)) if $directors;

		# Presenters (It's actually in the correct form)
		#my ($presenters) = $programme->findvalue ('./REZYSERIA');
		#$ce->{presenters} = parse_person_list(norm($presenters)) if $presenters;

		# Genre
      my ($genre) = $programme->findvalue ('./TYP');
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "TVP", $genre );
      AddCategory( $ce, $program_type, $categ );

      # Movie
      if($genre =~ /^film/i) {
        $ce->{program_type} = 'movie';
      } elsif($genre =~ /^serial/i) {
        $ce->{program_type} = 'series';
      }
      
      # Production Year
      if( $year ){
        $ce->{production_date} = $year . '-01-01';
      }

      # Grab season from the title
      my($ep2, $seasonroman, $seas, $episode, $to, $herpa);

      # Org title
      if($title_org ne "" and $title_org ne "." and $title ne $title_org) {
        $title_org =~ s/, ep\. (\d+)$//i;
        $ce->{original_title} = norm($title_org);
      }

      # Ranczo - odc. 94 (seria VIII, odc. 3) - Wybacz mnie => season = VIII, ep = 3
      if($title_full =~ /\(seria\s+(\S*?)(,|)\s+odc\.\s+(\d+)\)/) {
          ( $seasonroman, $herpa, $ep2 ) = ($title_full =~ /\(seria\s+(\S*?)(,|)\s+odc\.\s+(\d+)\)/ );
          if( (defined $ep2) and (defined $seasonroman) and isroman($seasonroman) )
          {
            my $romanseas = arabic($seasonroman);
            $title =~ s/$seasonroman//i;
            $title =~ s/\(s\. $romanseas\)//i;
            $ce->{title} =~ norm($title);

            # add it
            if(defined($romanseas)) {
                $ce->{episode} = sprintf( "%d . %d .", $romanseas-1, $ep2-1 );
            }
          }
      } elsif($title_org =~ /s\.\s+(\S*)(,|)\s+ep\.\s+(\d+)/) {
          ( $to, $seasonroman, $herpa, $ep2 ) = ($title_org =~ /(.*)\s+s\.\s+(\S*?)(,|)\s+ep\.\s+(\d+)/ );
          if( (defined $ep2) and (defined $seasonroman) and isroman($seasonroman) )
          {
            $ce->{original_title} = norm($to);
            my $romanseas = arabic($seasonroman);
            $title =~ s/$seasonroman//i;
            $title =~ s/\(s\. $romanseas\)//i;
            $ce->{title} =~ norm($title);

            # add it
            if(defined($romanseas)) {
                $ce->{episode} = sprintf( "%d . %d .", $romanseas-1, $ep2-1 );
            }
          }
      }

      progress("TVP: $chd->{xmltvid}: $time - $title");
      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
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

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }
  
  # Sometimes hour is 24, then it is 00
  if ($hour eq '24') {
  	$hour = '00';
  }
  
  # Sometimes hour is 25, then it is 01
  if ($hour eq '25') {
  	$hour = '01';
  }
  
  
  
  return sprintf( "%02d:%02d", $hour, $min );
}

1;

package NonameTV::Importer::SRF;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions.

Registration at: https://medienportal.srf.ch/app/
Webservice documentation available via: http://www.crosspoint.ch/index.php?is_presseportal_ws

TODO handle regional programmes on DRS

=cut

use Encode qw/decode encode/;
use utf8;
use Data::Dumper;
use IO::Uncompress::Unzip qw/unzip/;

use NonameTV qw/AddCategory AddCountry normLatin1 norm ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore}, 'Europe/Zurich' );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $date ) = ( $objectname =~ /^(.+)_(\d+-\d+-\d+)$/ );
  my ($year, $month, $day) = ( $date =~ /(\d+)-(\d+)-(\d+)$/ );

  if (!defined ($chd->{grabber_info})) {
    return (undef, 'Grabber info must contain channel id!');
  }

  my $dt = DateTime->new( year => $year, month => $month, day => $day );

  # http://www.srf.ch/medien/programm/?xml=1&from=20.07.2016&to=20.07.2016&channel=1
  my $url = sprintf( 'http://www.srf.ch/medien/programm/?xml=1&from=%s&to=%s&channel=%s', $dt->dmy('.'), $dt->dmy('.'), $chd->{grabber_info} );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub ContentExtension {
  return 'zip';
}

sub FilterContent {
  my $self = shift;
  my( $zref, $chd ) = @_;

  if (!($$zref =~ m/^PK/)) {
    return (undef, "returned data is not a zip file");
  }

  my $cref;
  unzip $zref => \$cref;

  #$cref = decode( 'utf-8', $cref );

  #$cref =~ s|\x{0d}$||g;      # strip carriage return from the line endings
  #$cref =~ s|\x{a0}+(?=<)||g; # strip trailing non-breaking whitespace
  #$cref = normLatin1( $$cref );

  #$cref = encode( 'utf-8', $cref );

  my $doc = ParseXml( \$cref );

  if( not defined $doc ) {
    return (undef, "Parse2Xml failed" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $doc = ParseXml ($cref);

  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $ns = $doc->find ('//SENDUNG');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my $date = $doc->findvalue( '//SENDUNG[1]/DATUM' );
  $date =~ s|(\d+)\.(\d+)\.(\d+)|$3-$2-$1|;
  $self->{datastorehelper}->StartDate( $date );

  foreach my $programme ($ns->get_nodelist) {
    my ($time) = ($programme->findvalue ('./ZEIT') =~ m|(\d+\:\d+)|);
    if( !defined( $time ) ){
      w( 'programme without start time!' );
    }else{
      my ($title) = $programme->findvalue ('./TITEL');
      my ($org_title) = $programme->findvalue ('./ORGTITEL');
      my ($cast) = $programme->findvalue ('./PERSONEN');

      my $season = $programme->findvalue( './SEASON' );
      my $episode = $programme->findvalue( './FOLGENR' );
      my $hd = $programme->findvalue( './HD' );

      my $ce = {
#        channel_id => $chd->{id},
        start_time => $time,
        title => norm(normLatin1($title)),
      };

      # Extra
      my $extra = {};
      $extra->{descriptions} = [];
      $extra->{qualifiers} = [];
      $extra->{images} = [];

      my ($subtitle) = $programme->findvalue ('./UNTERTITEL');
      my ($subtitle_org) = $programme->findvalue ('./ZUSATZTITEL');
      if( $subtitle ){
        $ce->{subtitle} = $subtitle;
      }

      my ($description) = $programme->findvalue ('./INHALT');
      if( !$description ){
        ($description) = $programme->findvalue ('./LEAD');
      }
      if( $description ){
        $ce->{description} = norm(normLatin1($description));
      }

      my ($genre) = $programme->findvalue ('./GENRE');
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "SRF", $genre );
      AddCategory( $ce, $program_type, $categ );

      my ($year) = $programme->findvalue ('./PRODJAHR');
      if( $year ){
        $ce->{production_date} = $year . '-01-01';
      }

      if($programme->findvalue ('./PRODLAND') and $programme->findvalue ('./PRODLAND') ne "") {
        my @conts = split(/,|\//, norm($programme->findvalue ('./PRODLAND')));
        my @countries;

        foreach my $c (@conts) {
            my ( $c2 ) = $self->{datastore}->LookupCountry( "SRF", norm($c) );
            push @countries, $c2 if defined $c2;
        }

        if( scalar( @countries ) > 0 )
        {
              $ce->{country} = join "/", @countries;
        }
      }

      # Cast
      if($cast) {
        $cast =~ s/^Mit/Mit:/; # Make it pretty
        $cast =~ s/^Ein Film von/Regie:/; # Alternative way
        my @sentences = (split_personen( $cast ), "");
        my( $actors, $dummy, $actors2, $directors, $writers, $guests, $guest, $presenter, $host, $producer );

        for( my $i=0; $i<scalar(@sentences); $i++ )
        {
            if( ( $actors ) = ($sentences[$i] =~ /^Mit\:(.*)/ ) )
            {
              $ce->{actors} = norm(parse_person_list(normLatin1($actors)));;
              $sentences[$i] = "";
            }
            elsif( ( $directors ) = ($sentences[$i] =~ /^Regie\:(.*)/ ) )
            {
                $directors =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{directors} = norm(parse_person_list(normLatin1($directors)));;
                $sentences[$i] = "";
            }
            elsif( ($dummy, $presenter ) = ($sentences[$i] =~ /^(Moderator|Moderation)\:(.*)/ ) )
            {
                $presenter =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{presenters} = norm(parse_person_list(normLatin1($presenter)));;
                $sentences[$i] = "";
            }
            elsif( ($host ) = ($sentences[$i] =~ /^Redaktion\:(.*)/ ) )
            {
                $host =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{commentators} = norm(parse_person_list(normLatin1($host)));;
                $sentences[$i] = "";
            }
            elsif( ( $producer ) = ($sentences[$i] =~ /^Produzent\:(.*)/ ) )
            {
                $producer =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{producers} = norm(parse_person_list(normLatin1($producer)));;
                $sentences[$i] = "";
            }
            elsif( ( $writers ) = ($sentences[$i] =~ /^Drehbuch\:(.*)/ ) )
            {
                $writers =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{writers} = norm(parse_person_list(normLatin1($writers)));;
                $sentences[$i] = "";
            }
            elsif( ( $actors2 ) = ($sentences[$i] =~ /^Sprecher\:(.*)/ ) )
            {
                $actors2 =~ s/\((.*?)\)//g; # Isn't a role.
                $ce->{actors} = norm(parse_person_list(normLatin1($actors2)));;
                $sentences[$i] = "";
            }
        }
      }



      $ce->{original_title} = norm(normLatin1($org_title)) if $org_title and $org_title ne $title;
      $ce->{original_subtitle} = norm(normLatin1($subtitle_org)) if $subtitle_org and $subtitle_org ne $subtitle;
      $ce->{quality} = "HDTV" if $hd eq "Ja";

      # EPISODES
      if($episode) {
        if($season) {
          $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
        } else {
          $ce->{episode} = sprintf( " . %d . ", $episode-1 );
        }
      }

      # Images
      my $imgs = $programme->find( './/BILD' );
      foreach my $item ($imgs->get_nodelist)
      {
        my $image = $item->find('./URL_300DPI')->to_literal;
        my $imgtit = $item->find('./TITEL')->to_literal;
        $imgtit =~ s/\:$//;
        my( $copyright) = ($item->find('./LEGENDE')->to_literal =~ /\(Copyright (.*?)\)/ );

        push $extra->{images}, { url => $image, title => $imgtit, copyright => $copyright, source => "SRF" };
      }

      $self->{datastorehelper}->AddProgramme( $ce );
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

sub split_personen
{
  my( $t ) = @_;

  return () if not defined( $t );

  $t =~ s/(\S+)\:\s+([\(A-ZÅÄÖ])/;;$1: $2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
  }

  return @sent;
}

1;

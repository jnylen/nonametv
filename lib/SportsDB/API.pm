#===============================================================================
#       MODULE:  SportsDB::API
#       AUTHOR:  Joakim Nylén, https://honeybee.it
#      COMPANY:  dotMedia Networks
#===============================================================================

use strict;
use warnings;

package SportsDB::API;

use HTTP::Request::Common;
use JSON -support_by_pp;
use Encode qw(encode decode);
use Data::Dumper;
use Debug::Simple;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;
use Object::Tiny qw(apikey apiurl lang debug client encoder json);
use WWW::Mechanize::GZip;

### config
### NoUpdate won't check the http server for updates in 12 hours after first fetch.
### Verbose prints all calls even if its cached so a lot of spam.
use NonameTV::Config qw/ReadConfig/;
use HTTP::Cache::Transparent ( BasePath => ReadConfig()->{ContentCachePath} . '/SportsDB', Verbose   => 1, NoUpdate  => 12*60*60 );

sub new {
    my $self = bless {};

    my $args;
    if (ref $_[0] eq 'HASH') {
        # Subroutine arguments by hashref
        $args = shift;
    } else {
        # Traditional subroutine arguments
        $args = {};
        ($args->{cache}) = @_;
    }

    # Nonametv conf
    my $conf = ReadConfig( );

    $args->{useragent} ||= "nonametv (http://nonametv.org)";

    $self->{ua} = WWW::Mechanize::GZip->new( agent => $args->{useragent} );

    return $self;
}

# Download binary data
sub _download {
    my ($self, $fmt, $url, @parm) = @_;

    # Make URL
    $url = sprintf($fmt, $url, @parm);

    #$url =~ s/\$/%24/g;
    $url =~ s/#/%23/g;
    #$url =~ s/\*/%2A/g;
    #$url =~ s/\!/%21/g;
    #&verbose(2, "TVRage::Cache: download: $url\n");
    utf8::encode($url);

    # Make sure we only download once even in a session
    return $self->{dload}->{$url} if defined $self->{dload}->{$url};

    # Download URL
    my $res = $self->{ua}->get($url);

    if ($res->{_content} =~ /(?:404 Not Found|The page your? requested does not exist)/i) {
        #&warning("TVRage::Cache: download $url, 404 Not Found\n");
        $self->{dload}->{$url} = 0;
        return undef;
    }
    $self->{dload}->{$url} = $res->{_content};
    return $res->{_content};
}

# Download Json, parse JSON, and return hashref
sub _downloadJson {
    my ($self, $fmt, @parm) = @_;

    # Download XML file
    my $data = $self->_download($fmt, $self->{apiURL}, @parm, 'json');
    return undef unless $data;

    my $json = new JSON->allow_nonref;
    $data = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$data);

    return undef if !defined($data);

    # Return process XML into hashref
    return undef unless $data;
    return $data;
}

sub eventInfo {
    my ($self, $sid) = @_;
    my $series = $self->{cache};

    &debug(2, "SportsDB: getEvents: $sid, $sid\n");
    my $data = $self->_downloadJson("http://www.thesportsdb.com/api/v1/json/1/searchevents.php?e=Chelsea_vs_West_Brom");

    print Dumper( $data );
    return $data;
}

1;

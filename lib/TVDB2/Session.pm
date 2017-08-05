package TVDB2::Session;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# LOAD CPAN MODULES
#######################
use JSON::MaybeXS;
use Data::Dumper;
use Encode qw();
use URI::Encode qw();
use URI::Escape;
use Params::Validate qw(validate_with :types);
use Locale::Codes::Language qw(all_language_codes);
use Object::Tiny qw(apikey apiurl lang debug client encoder json username userkey);
use WWW::Mechanize::GZip;
use Sub::Retry;

### config
### NoUpdate won't check the http server for updates in 48 hours after first fetch.
### Verbose prints all calls even if its cached so a lot of spam.
### Cache::FileCache is used to cache the token bearer
use NonameTV::Config qw/ReadConfig/;
use HTTP::Cache::Transparent;
use Cache::FileCache;


#######################
# VERSION
#######################
our $VERSION = '0.0.1';

#######################
# PACKAGE VARIABLES
#######################

# Valid language codes
my %valid_lang_codes = map { $_ => 1 } all_language_codes('alpha-2');

# Default Headers
my $default_headers = {
    'Accept'       => 'application/json',
    'Content-Type' => 'application/json'
};

# Default User Agent
my $default_ua = 'xmltvse-tvdb2-client';

#######################
# PUBLIC METHODS
#######################

## ====================
## Constructor
## ====================
sub new {
    my $class = shift;
    my %opts  = validate_with(
        params => \@_,
        spec   => {
            apikey => {
                type => SCALAR,
            },
            username => {
                type => SCALAR,
            },
            userkey => {
                type => SCALAR,
            },
            apiurl => {
                type     => SCALAR,
                optional => 1,
                default  => 'https://api.thetvdb.com',
            },
            lang => {
                type      => SCALAR,
                optional  => 1,
                default   => 'en',
                callbacks => {
                    'valid language code' =>
                      sub { $valid_lang_codes{ lc $_[0] } },
                },
            },
            client => {
                type     => OBJECT,
                isa      => 'WWW::Mechanize',
                optional => 1,
                default  => WWW::Mechanize::GZip->new( agent => $default_ua, headers => $default_headers ),
            },
            encoder => {
                type     => OBJECT,
                isa      => 'URI::Encode',
                optional => 1,
                default  => URI::Encode->new(),
            },
            json => {
                type     => OBJECT,
                can      => [qw(decode)],
                optional => 1,
                default  => JSON::MaybeXS->new(),
            },
            debug => {
                type     => BOOLEAN,
                optional => 1,
                default  => 0,
            },
        },
    );

  $opts{lang} = lc $opts{lang} if $opts{lang};

  HTTP::Cache::Transparent::init ( {BasePath => ReadConfig()->{ContentCachePath} . '/Tvdb2/'.$opts{lang},
                                   Verbose   => 1, NoUpdate  => 48*60*60} );

  my $self = $class->SUPER::new(%opts);

  return $self;
}

## ====================
## JWT Bearer code
## ====================
sub bearer {
  my ( $self, $args ) = @_;

  my $cache = new Cache::FileCache( );
  my $name  =  'Tvdb2.token';
  my $token = $cache->get( $name );

  # Not found?
  if(!defined $token) {
    warn "DEBUG: DIDNT GET token from cache\n" if $self->debug;
    my $url = $self->apiurl . '/login';
    $url = $self->encoder->encode($url);

    my $data = {
      apikey => $self->apikey,
      userkey => $self->userkey,
      username => $self->username
    };

    my $n = shift;
    warn "DEBUG: POST -> $url\n" if $self->debug;
    my $response = $self->client->post($url, Content => encode_json($data));

    # Debug
    if ( $self->debug ) {
        warn "DEBUG: Got a successful response\n" if $response->{_msg} eq "OK";
    }

    # Return
    #return undef unless $self->_check_status($response);
    if ( $args->{want_headers} and exists $response->{_headers} ) {
      # Return headers only
      return $response->{_headers};
    }

    return undef unless $response->{_content};  # Blank Content

    $token = $self->json->decode(
          Encode::decode( 'utf-8-strict', $response->content ) );
    $token = $token->{token};
    $cache->set( $name, $token, "20 hours" );
  } elsif($self->debug) {
    warn "DEBUG: GOT token from cache\n" if $self->debug;
  }

  return $token;
}

## ====================
## Talk
## ====================
sub talk {
  my ( $self, $args ) = @_;

  # Build Call
  my $token = $self->bearer;
  my $url = URI->new( $self->apiurl . '/' . $args->{method} );
  if ( $args->{params} ) {
    $url->query_form($args->{params});
  } ## end if ( $args->{params} )

  # Encode
  $url = $self->encoder->encode($url);

  # Talk (retry 3 times, 10s delay each time)
  my $res = retry 3, 10, sub {
    my $n = shift;
    warn "DEBUG: GET -> $url (times: $n)\n" if $self->debug;
    my $client = WWW::Mechanize::GZip->new( agent => $default_ua, headers => {
        'Accept'       => 'application/json',
        'Content-Type' => 'application/json',
        "Authorization" => "Bearer $token",
        'Accept-Language' => $self->lang
    } );
    my $response = $client->get($url);

    # Debug
    if ( $self->debug ) {
        warn "DEBUG: Got a successful response\n" if $response->{_msg} eq "OK";
    }

    # Return
    return undef unless $self->_check_status($response);
    if ( $args->{want_headers} and exists $response->{_headers} ) {
      # Return headers only
      return $response->{_headers};
    }

    return undef unless $response->{_content};  # Blank Content

    return $self->json->decode(
          Encode::decode( 'utf-8-strict', $response->content ) ); # Real Response
  }, sub {
      my $res = shift;
      defined $res ? 0 : 1;
  };
}

## ====================
## PAGINATE RESULTS
## ====================
sub paginate_results {
  my ( $self, $args ) = @_;

  my $response = $self->talk($args);
  my $results = $response->{data} || [];

  # Paginate
  if (    $response->{links}->{next} and $response->{links}->{last}
      and ( $response->{links}->{last} > ($response->{links}->{next} - 1) ) )
  {
      my $page_limit = $args->{max_pages} || '10';
      my $current_page = ($response->{links}->{next} - 1);
      while ($page_limit) {
        last if ( $current_page == $page_limit );
          $current_page++;
          $args->{params}->{page} = $current_page;
          my $next_page = $self->talk($args);
          push @$results, @{ $next_page->{data} },;
        last if ( !defined $next_page->{links}->{next} );
          $page_limit--;
      } ## end while ($page_limit)
  } ## end if ( $response->{page}...)

  # Done
  return @$results if wantarray;
  return $results;
}

#######################
# INTERNAL
#######################

# Check Response status
sub _check_status {
    my ( $self, $response ) = @_;

    if ( $response->{_msg} eq "OK" ) {
      return 1;
    }

    if ( $response->{_content} ) {
        my ( $code, $message );
        my $ok = eval {

            my $status = $self->json->decode(
                Encode::decode( 'utf-8-strict', $response->content ) );

            $message = $status->{Error};

            1;
        };

        if ( $ok and $code and $message ) {
            carp sprintf( 'TVDB2 API Error: %s', $message );

            # 34 = Not Found (return 1 to not retry)
            if($message =~ /not found$/i) {
              return 1;
            }
        }
    } ## end if ( $response->{content...})

  return undef;
} ## end sub _check_status

#######################
1;

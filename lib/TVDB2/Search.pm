package TVDB2::Search;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# LOAD CPAN MODULES
#######################
use Params::Validate qw(validate_with :types);
use Object::Tiny qw(session);

#######################
# LOAD DIST MODULES
#######################
use TMDB::Session;

#######################
# VERSION
#######################
our $VERSION = '0.0.1';

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
            session => {
                type => OBJECT,
                isa  => 'TVDB2::Session',
            },
        },
    );

    my $self = $class->SUPER::new(%opts);
  return $self;
} ## end sub new

## ====================
## Search TV Shows
## ====================
sub series {
  my $self    = shift;
  my $string = shift || {};
  my $params = shift || {};

  # Trim
  $string =~ s{(?:^\s+)|(?:\s+$)}{};
  $params->{name} = $string;

  warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
      {
          method => 'search/series',
          params => $params,
      }
  );
} ## end sub tv

#######################
# PRIVATE METHODS
#######################

## ====================
## Search
## ====================
sub _search {
    my $self = shift;
    my $args = shift;
  return $self->session->paginate_results($args);
} ## end sub _search

#######################
1;

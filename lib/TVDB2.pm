package TVDB2;

#######################
# LOAD MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# VERSION
#######################
our $VERSION = '0.0.1';

#######################
# LOAD CPAN MODULES
#######################
use Object::Tiny qw(session);

#######################
# LOAD DIST MODULES
#######################
use TVDB2::Session;
use TVDB2::Series;
use TVDB2::Episode;
use TVDB2::Search;

#######################
# PUBLIC METHODS
#######################

## ====================
## CONSTRUCTOR
## ====================
sub new {
    my ( $class, @args ) = @_;
    my $self = {};
    bless $self, $class;

    # Init Session
    $self->{session} = TVDB2::Session->new(@args);
  return $self;
} ## end sub new

## ====================
## TMDB OBJECTS
## ====================
sub series { return TVDB2::Series->new( session => shift->session, @_ ); }
sub search { return TVDB2::Search->new( session => shift->session, @_ ); }
sub episode { return TVDB2::Episode->new( session => shift->session, @_ ); }


#######################
1;

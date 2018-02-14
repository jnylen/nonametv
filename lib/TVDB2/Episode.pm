package TVDB2::Episode;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# LOAD CPAN MODULES
#######################
use Object::Tiny qw(id session);
use Params::Validate qw(validate_with :types);
use Locale::Codes::Country qw(all_country_codes);

#######################
# LOAD DIST MODULES
#######################
use TVDB2::Session;

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
            id => {
                type => SCALAR,
            },
        },
    );

    my $self = $class->SUPER::new(%opts);
  return $self;
} ## end sub new

## ====================
## INFO
## ====================
sub info {
    my $self   = shift;
    my $params = {};
    my $info = $self->session->talk(
        {
            method => 'episodes/' . $self->id
        }
    );
  return unless $info;
    $self->{id} = $info->{id};  # Reset TMDB ID
  return $info;
} ## end sub info

## ====================
## VERSION
## ====================
sub version {
    my ($self) = @_;
    my $response = $self->session->talk(
        {
            method       => 'episode/' . $self->id(),
            want_headers => 1,
        }
    ) or return;
    my $version = $response->{etag} || q();
    $version =~ s{"}{}gx;
  return $version;
} ## end sub version

#######################
1;

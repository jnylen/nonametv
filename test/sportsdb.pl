#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;

use SportsDB::API;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;
use Data::Dumper;

# need config for main content cache path
my $conf = ReadConfig( );

my $cachedir = $conf->{ContentCachePath} . '/SportsDB';

my $sdb = SportsDB::API->new();

print Dumper($sdb->eventInfo("lel")->{"event"}[0]->{"strLeague"});

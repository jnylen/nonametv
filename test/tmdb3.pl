#!/usr/bin/perl

use strict;
use utf8;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
#use DateTime;
#use Encode;

use NonameTV::Factory qw/CreateAugmenter CreateDataStore/;

my $ds = CreateDataStore( );

my $augmenter = CreateAugmenter( 'Tmdb3', $ds, 'de' );

#my $ce = {
#	'title' => 'Blues Brothers',
#	'production_date' => '1980-01-01',
#	'directors' => 'John Landis',
#};

# alias name of director
#my $ce = {
#	'title' => 'Mala',
#	'production_date' => '2013-01-01',
#	'directors' => 'Israel Adrián Caetano', # <- this is an alternate name of the director
#};

# many aliases
#my $ce = {
#	'title' => 'Das Todesduell der Tigerkralle',
#	'production_date' => '1977-01-01',
#	'directors' => 'Chu Yuan',
#};

# the director really is the writer
my $ce = {
	'title' => 'Schneeweisschen und Rosenrot',
	'production_date' => '2012-01-01',
	'directors' => 'Mario Giordano',
};


my $rule = {
	'augmenter' => 'Tmdb3',
	'matchby' => 'title',
};

my ( $newprogram, $result ) = $augmenter->AugmentProgram( $ce, $rule );

print Dumper( \$result, \$newprogram );

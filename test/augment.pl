#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;

use NonameTV::Augmenter;
use NonameTV::Factory qw/CreateDataStore/;

my $ds = CreateDataStore( );
my $batchid = 'svt1.svt.se_2015-07-27';
printf( "augmenting %s...\n", $batchid );

my $augmenter = NonameTV::Augmenter->new( $ds );

$augmenter->AugmentBatch( $batchid );

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

my $dt = DateTime->now( time_zone => 'UTC' );
$dt->add( days => 3 );

my $batchid = 'kanal5.se_' . $dt->year .'-'.$dt->week;
printf( "augmenting %s...\n", $batchid );

my $augmenter = NonameTV::Augmenter->new( $ds );

$augmenter->AugmentBatch( $batchid );
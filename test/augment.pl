#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;

use NonameTV::Augmenter;
use NonameTV::Factory qw/CreateDataStore/;
NonameTV::Log::SetVerbosity( 2 );

my $ds = CreateDataStore( );
my $batchid = 'joi.mediaset.dev_2018-05-09';
printf( "augmenting %s...\n", $batchid );

my $augmenter = NonameTV::Augmenter->new( $ds );

$augmenter->AugmentBatch( $batchid );

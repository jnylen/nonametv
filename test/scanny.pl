#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;
use Data::Dumper;
#$subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
my $subtitle = "Folge 63: 'Mr. Monk im Müll'";
my ($episode, $subtitle2);
if(($episode, $subtitle2) = ($subtitle =~ /^Folge (\d+)\: \'(.*?)\'$/i)) {
	print Dumper($episode, $subtitle2);
}

#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use DateTime;

my $text = "2015-08-20T22:45:00.000Z";

print Dumper(ParseDateTime($text)->ymd("-"));
print Dumper(ParseDateTime($text)->hms(":"));

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "UTC"
  );

  return $dt;
}

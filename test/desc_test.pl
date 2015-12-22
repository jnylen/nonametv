#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use DateTime;


    my $start = ParseDateTime( "2015-12-26 20:10:00" );
    my $end = ParseDateTime( "2015-12-26 22:10:00" );
    my $diff  = $end - $start;

    print Dumper($diff->in_units('minutes'));




sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/ );

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

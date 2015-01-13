#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use Data::Dumper;

use Test::More 'no_plan';

my @tests = (
    [ { iln => 69, ppns => ['211816442','523597266'] },
      { '211816442' => 1, '523597266' => 1} ]
);

foreach my $test (@tests) {
    #print Dumper( $test->[0] )
    my %result = itemcount( $test->[0] );
    is_deeply( \%result, $test->[1] );
}

# Parameter als Hash oder hashref, rückgabe als Hash
# iln
# 
sub itemcount {
    my (%param) = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

    $param{ppns} = join("\n", @{ $param{ppns} })
        if ref($param{ppns}) && ref($param{ppns}) eq 'ARRAY';

    delete $param{html};
    $param{csv} = 1;

    my $ua = LWP::UserAgent->new;
    my $url = "http://ws.gbv.de/itemcount/";

    my $response = $ua->post( $url, \%param );
    if ($response->is_success) {
        my @lines = split "\n", $response->decoded_content;
        my %result = map { $_ =~ /^([^;]+);(.*)$/ ? ($1 => $2) : ($_ => undef) }
                    @lines;
        return %result;
    } else {
        return;
    }
}
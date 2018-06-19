#!/usr/bin/perl -T
# Yes, we want to make sure things work in taint mode

#
# Copyright (C) 2015 Joelle Maslak
# All Rights Reserved - See License
#

# This tests the basic Term::Tmux::Layout

use strict;
use warnings;
use autodie;

use Carp;
use Test::More tests => 16;

# Instantiate the object
require_ok('Term::Tmux::Layout');
my $layout = Term::Tmux::Layout->new();
ok( defined($layout), "Constructer returned object" );

my @layouts = (
    [ '364x94,0,0,9', 'c846' ],
    [
        '364x94,0,0{91x94,0,0,45,90x94,92,0,48,90x94,183,0,46,90x94,274,0,47}',
        '4f55'
    ],
    [
'364x94,0,0[364x31,0,0{91x31,0,0,0,90x31,92,0,1,90x31,183,0,34,90x31,274,0,30},364x30,0,32{182x30,0,32,39,90x30,183,32,7,90x30,274,32,40},364x31,0,63{182x31,0,63,8,181x31,183,63,44}]',
        'f245'
    ]
);

for ( my $i = 0; $i < scalar(@layouts); $i++ ) {
    my $test = $layouts[$i];

    my $result = $layout->checksum( $test->[0] );
    is( $result, $test->[1], "Checksum proper for layout $i" );
}

@layouts = (
    [ 'x',          'acdf,80x24,0,0,100' ],
    [ 'xx',         'acdf,80x24,0,0,100' ],
    [ "x\nx",       'acdf,80x24,0,0,100' ],
    [ "xx\nxx",     'acdf,80x24,0,0,100' ],
    [ "xY",         'ab1f,80x24,0,0{39x24,0,0,100,41x24,40,0,100}' ],
    [ "xxYY",       'ab1f,80x24,0,0{39x24,0,0,100,41x24,40,0,100}' ],
    [ "xY\nxY",     'ab1f,80x24,0,0{39x24,0,0,100,41x24,40,0,100}' ],
    [ "xxYY\nxxYY", 'ab1f,80x24,0,0{39x24,0,0,100,41x24,40,0,100}' ],
    [ "xYY\nxYY",   'b6cb,80x24,0,0{26x24,0,0,100,54x24,27,0,100}' ],
    [
        "xYYz",
        '4f76,80x24,0,0{19x24,0,0,100,61x24,20,0{40x24,20,0,100,21x24,60,0,100}}'
    ],
);

# Some layout tests
for ( my $i = 0; $i < scalar(@layouts); $i++ ) {
    my $result = $layout->layout( $layouts[$i]->[0] );
    is( $result, $layouts[$i]->[1], "Layout test $i" );
}

# Layout test using multiple arguments
my $result = $layout->layout( 'xxYY', 'xxYY' );
is( $result,
    'ab1f,80x24,0,0{39x24,0,0,100,41x24,40,0,100}',
    'Layout test multiple arguments'
);


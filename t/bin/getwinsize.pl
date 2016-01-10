#!/usr/bin/perl

use strict;
use warnings;

my $port = shift(@ARGV);

use lib @ARGV;
use IO::Socket::IP;
require Term::Tmux::Layout;

my $sock = IO::Socket::IP->new(
    PeerPort => $port,
    PeerAddr => '127.0.0.1',
    Proto    => 'tcp'
) or die "Cannot open client socket: $!";

my $layout = Term::Tmux::Layout->new();
my ($x, $y) = $layout->get_window_size();

if (defined($y)) {
    print $sock "${x}x${y}\n";
} else {
    print $sock "0\n";
}

close $sock;

#!/usr/bin/perl

use strict;
use warnings;

my $port = shift(@ARGV);

use IO::Socket::INET;

my $sock = IO::Socket::INET->new(
    PeerPort => $port,
    PeerAddr => '127.0.0.1',
    Proto    => 'tcp'
) or die "Cannot open client socket: $!";

# Get the libraries
my $line = <$sock>;
chomp($line);
use lib split('|', $line);

# Do the test

require Term::Tmux::Layout;

my $layout = Term::Tmux::Layout->new();
my ($x, $y) = $layout->get_window_size();

if (defined($y)) {
    print $sock "${x}x${y}\n";
} else {
    print $sock "0\n";
}

close $sock;

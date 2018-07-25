#!/usr/bin/perl
# Because we call out to system, using the default path, we can expect
# taint mode to be unhappy.  So don't "prove -t" this script.

#
# Copyright (C) 2015 Joelle Maslak
# All Rights Reserved - See License
#

# This tests interaction with tmux.

use strict;
use warnings;

use Carp;
use Config;
use Cwd qw/cwd/;
use File::Spec;
use IO::Socket::IP; # Used by child script, but defined here to ensure that
                    # Dist::Zilla picks up the dependency.
use Test::More;
use Time::Out;

# my $tests = 4;
my $DIAG = undef;

# Check for tmux
my $result = 1;
my $v;
{
    no warnings 'exec';
    $v = `tmux -V`;
    $result = $?;
}

if ($result == 0) {
#    plan tests => $tests;
    if ($v =~ m/^(:?tmux)? 1\./) {
        # We can support tmux < 2, but the syntax of the
        # command line for new-window is different, so the
        # tests (not the actual code) fails.  Let's just
        # skip the tests in this case.
        diag("tmux version $v too old for tests to use");
        plan skip_all => 'not testing tmux version < 2';
    }
} else {
    plan skip_all => 'tmux not found';
}

ok($result == 0, 'tmux version exec successful');
ok($v, 'got tmux version number');
diag("tmux version: $v");

$ENV{TMUX} = 1;  # In case we are in a tmux window
my $sn = "test_tmux_session_${$}_perl_" . int(rand(1000000)) . '_';

$result = system('tmux', 'new-session', '-d', '-x100', '-y100', '-s', $sn);
ok(!$result, 'created tmux session');

my (@sessions) = `tmux list-sessions`;
ok($? == 0, 'tmux list-sessions exec successful');
ok(scalar(@sessions), 'at least one sessions in list');

@sessions = grep { /$sn/ } @sessions ;
ok(scalar(@sessions), 'new session in session list');

Time::Out::timeout 15 => sub {
    get_size($sn);
};
if ($@) {
    fail "Resolution read failed due to timeout";
}

$result = system('tmux', 'kill-session', '-t', $sn);
ok(!$result, 'destroyed tmux session');

done_testing;

sub get_size {
    my $sn = shift;

    my $sock = IO::Socket::IP->new(
        LocalHost => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        (($^O eq 'MSWin32') ? () : (ReuseAddr => 1))
    );

    my $port = $sock->sockport;
    ok($port, 'listening port created');

    my $pid = fork();
    if ($pid > 0) { # Parent
        # We just fail through this if statement.
    } elsif ($pid == 0) { # Child
        my $dir = cwd();

        # Make sure that we have a the same includes
        diag "PERL5LIB (pre): ".$ENV{PERL5LIB} if $DIAG;
        $ENV{PERL5LIB} = join $Config{path_sep}, @INC;
        diag "PERL5LIB (post): ".$ENV{PERL5LIB} if $DIAG;

        my $getwinsize =
        File::Spec->catfile($dir, 't', 'bin', 'getwinsize.pl');

        diag join(' ', 'tmux', 'new-window', '-n', 'test', '-t', $sn,
            ${Config{perlpath}}, $getwinsize, $port) if $DIAG;
        system('tmux','new-window','-n','test','-t',$sn,
            ${Config{perlpath}}, $getwinsize, $port);
        exit;
    } else {
        fail("Fork failed");
    }

    my $resolution;

    my $remote = $sock->accept();
    print $remote join('|', @INC);
    print $remote "\n";

    my $line = <$remote>;
    chomp($line);
    $resolution = $line;

    ok($resolution, "Got remote resolution");
    if (defined($resolution)) {
        diag("Resolution: $resolution");

        my ($x, $y) = $resolution =~ /(\d+)x(\d+)/;
        if (($x >= 98) && ($x <= 100)) {
            pass('X resolution is within limits');
        } else {
            fail('X resolution is outside limits');
        }
        if (($y >= 98) && ($y <= 100)) {
            pass('Y resolution is within limits');
        } else {
            fail('Y resolution is outside limits');
        }
    }
    close $remote;
    close $sock;
}


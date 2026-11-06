#!/usr/bin/perl
# Copyright (c) 2026 Kevnnard
# This file is licensed under the SmartWindow Public Non-Commercial License v1.1.
#
# Runs a command as a child and ends it when the watched process (SmartWindow)
# is gone, even after a crash. The vendored adapter stream waits in a run loop
# and only notices a dead parent on its next write, so it runs under this guard.
# Usage:
#   /usr/bin/perl parent-guard.pl <watched pid> /absolute/command [arguments...]
#
# The child inherits stdin, stdout and stderr. The guard polls every second and,
# once its parent is launchd (PID 1) or the watched PID no longer exists, sends
# TERM to the child, waits up to 1 s, then KILL. TERM and INT sent to the guard
# are forwarded the same way. The guard exits with the child's status.

use strict;
use warnings;
use POSIX qw(:sys_wait_h);
use Errno qw(ESRCH);

my ($watched, @command) = @ARGV;
die "parent-guard: usage: parent-guard.pl <watched pid> /absolute/command [arguments...]\n"
    unless defined $watched && $watched =~ /^[0-9]+$/ && $watched > 1
        && @command && $command[0] =~ m{^/};

my $forward;
# Installed before fork so a signal right after it is never lost; exec resets
# them to the default in the child. CHLD only wakes the sleep below.
$SIG{TERM} = sub { $forward //= 'TERM' };
$SIG{INT} = sub { $forward //= 'INT' };
$SIG{CHLD} = sub { };

my $child = fork();
die "parent-guard: fork failed: $!\n" unless defined $child;
if ($child == 0) {
    { no warnings 'exec'; exec { $command[0] } @command; }
    POSIX::_exit(127);
}

sub exit_like_child {
    my ($status) = @_;
    exit(WEXITSTATUS($status)) if WIFEXITED($status);
    exit(128 + WTERMSIG($status)) if WIFSIGNALED($status);
    exit 1;
}

sub watched_gone {
    return 1 if getppid() == 1;
    return !kill(0, $watched) && $! == ESRCH;
}

sub end_child {
    my ($signal) = @_;
    kill $signal, $child;
    for (1 .. 20) {
        exit_like_child($?) if waitpid($child, WNOHANG) == $child;
        select(undef, undef, undef, 0.05);
    }
    kill 'KILL', $child;
    waitpid($child, 0);
    exit_like_child($?);
}

for (;;) {
    exit_like_child($?) if waitpid($child, WNOHANG) == $child;
    end_child($forward) if defined $forward;
    end_child('TERM') if watched_gone();
    sleep 1;
}

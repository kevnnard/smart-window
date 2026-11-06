#!/usr/bin/perl
# Copyright (c) 2026 Kevnnard
# This file is licensed under the SmartWindow Public Non-Commercial License v1.1.
#
# Runs libMediaSessionsHelper.dylib inside /usr/bin/perl (an Apple-signed
# process, which mediaremoted answers). Usage:
#   /usr/bin/perl media-sessions.pl /absolute/path/libMediaSessionsHelper.dylib

use strict;
use warnings;
use DynaLoader;

my $path = $ARGV[0];
die "media-sessions: usage: media-sessions.pl /absolute/path/libMediaSessionsHelper.dylib\n"
    unless defined $path && $path =~ m{^/};
die "media-sessions: helper not found at $path\n" unless -f $path;

my $lib = DynaLoader::dl_load_file($path, 0)
    or die "media-sessions: cannot load $path: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($lib, "MediaSessionsHelperRun")
    or die "media-sessions: MediaSessionsHelperRun not found in $path: " . DynaLoader::dl_error() . "\n";
my $run = DynaLoader::dl_install_xsub("main::media_sessions_run", $symbol)
    or die "media-sessions: cannot install MediaSessionsHelperRun\n";

&$run();
# The helper loops until its parent exits; returning means it gave up.
exit 1;

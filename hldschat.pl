#!/usr/bin/env perl

# HLDS chat log parser "hldschat.pl", generates chat log files in HTML
#
# Copyright 2017, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.16.0;

use utf8;
use strict;
use warnings;

use HTML::Entities;

my ($stats, @chats);

if (@ARGV != 1) {
   say "Usage: $0 <logfile>";
   exit;
}
elsif (! -f $ARGV[0] || ! -r $ARGV[0]) {
   say "$ARGV[0] is not a regular file or can't be read.";
   exit;
}

unless (open my $fh, '<', $ARGV[0]) {
   die "opening file failed";
}
else {
   while (my $line = <$fh>) {
      chomp $line;
      push(@chats, sprintf('%s %s: %s', $1, encode_entities($2), encode_entities($4))) if ($line =~ m!^L [0-9]{2}/[0-9]{2}/[0-9]{4} - ([0-9]{2}:[0-9]{2}:[0-9]{2}): "(.+)<[0-9]+><STEAM_(0:[01]:[0-9]+)><players>" say "(.+)"$!);
   }
   close $fh;
}

say "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Chat Log</title></head><body><code>\n";
say "$_<br>" for (@chats);
say "</code></body></html>";

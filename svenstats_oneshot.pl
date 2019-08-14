#!/usr/bin/env perl

# Sven Co-op (svends) log parser "svenstats_oneshot.pl"
#
# Copyright 2016-2019, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.16.0;

use utf8; 
use strict; 
use warnings; 

use autodie;

no warnings 'experimental::smartmatch';

use Data::Dumper;
use MaxMind::DB::Reader;
use Math::BigFloat;
use File::Slurp;
use File::Basename;

### config

my $geo = '/usr/share/GeoIP/GeoLite2-City.mmdb';

###

my ($dbh, $stats, $maps);

if (@ARGV != 1) {
   say "Usage: $0 <logfile>";
   exit;
}
elsif (! -f $ARGV[0] || ! -r $ARGV[0]) {
   say "$ARGV[0] is not a regular file or can't be read.";
   exit;
}

my $today = fileparse( $ARGV[0], qw(.log) );
my @lines = read_file( $ARGV[0], binmode => ':raw', chomp => 1 ) ;

while (my $in = splice(@lines, 0, 1)) {
   next if (length($in) < 28);

   my $line = substr($in, 0, 2).substr($in, 25);

   if ($line =~ /^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><>" connected, address "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):/) {
      $$stats{$3}{name} = $1;
      $$stats{$3}{id}   = $2;
      $$stats{$3}{ip}   = $4;
      $$stats{$3}{joins}++;
      $$stats{$3}{datapoints} = 0 unless(defined $$stats{$3}{datapoints});
   }
   elsif ($line =~ /^L ".+<[0-9]+><STEAM_(0:[01]:[0-9]+)><players>" has entered the game/) {
      $$stats{$1}{joins}++;
   }
   elsif ($line =~ /^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><players>" stats: frags="(-?[0-9]+\.[0-9]{2})" deaths="([0-9]+)"/) {
      $$stats{$3}{score}      = Math::BigFloat->bzero unless(defined $$stats{$3}{score});
      $$stats{$3}{lastscore}  = Math::BigFloat->bzero unless(defined $$stats{$3}{lastscore});
      $$stats{$3}{deaths}     = 0 unless(defined $$stats{$3}{deaths});
      $$stats{$3}{lastdeaths} = 0 unless(defined $$stats{$3}{lastdeaths});

      my $score     = Math::BigFloat->new($4);
      my $lastscore = $score->copy;
      my $idx       = $2.'x'.(defined $$stats{$3}{joins} ? $$stats{$3}{joins} : 1);
      
      if ($score->bacmp($$stats{$3}{lastscore})) {
         if (exists $$stats{$3}{idx} && $idx eq $$stats{$3}{idx}) {
            my $diff = $score->bsub($$stats{$3}{lastscore});
            $$stats{$3}{score}->badd($diff);
         }
         else {
            $$stats{$3}{score}->badd($score);
         }
      }

      if ($5 != $$stats{$3}{lastdeaths}) {
         if (exists $$stats{$3}{idx} && $idx eq $$stats{$3}{idx}) {
            my $diff = $5 - $$stats{$3}{lastdeaths};
            $$stats{$3}{deaths} += $diff;
         }
         else {
            $$stats{$3}{deaths} += $5;
         }
      }

      $$stats{$3}{name}       = $1;
      $$stats{$3}{id}         = $2;
      $$stats{$3}{idx}        = $idx;
      $$stats{$3}{lastscore}  = $lastscore->copy;
      $$stats{$3}{lastdeaths} = $5;
      $$stats{$3}{datapoints}++;
   }
}

my $gi = MaxMind::DB::Reader->new(file => $geo);
my $c = 1;

foreach my $key (sort { $$stats{$b}{datapoints} <=> $$stats{$a}{datapoints} } keys %{$stats}) {
   my ($country, $lat, $lon);

   if (defined $$stats{$key}{ip}) {
      my $record  = $gi->record_for_address($$stats{$key}{ip});

      if ($record) {
         $country = lc($record->{country}{iso_code});
      }
   }

   printf("%s %s %s %s %s\n",
      defined $$stats{$key}{score}      ? $$stats{$key}{score}      : 0,
      defined $$stats{$key}{deaths}     ? $$stats{$key}{deaths}     : 0,
      defined $$stats{$key}{datapoints} ? $$stats{$key}{datapoints} : 0,
      defined $country                  ? $country                  : defined $$stats{$key}{geo}  ? $$stats{$key}{geo}  : 'white',
      defined $$stats{$key}{name}       ? $$stats{$key}{name}       : '?',
   ) if ($$stats{$key}{datapoints} > 30);

   $c++;
   last if ($c > 25);
}

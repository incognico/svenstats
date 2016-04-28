#!/usr/bin/env perl

# Sven Co-op (svends) log parser "svenstats.pl"
#
# Copyright 2016, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.16.0;

use utf8; 
use strict; 
use warnings; 

use DBI;
use Data::Dumper;
use Geo::IP;
use Math::BigFloat;

### config

my $db     = "$ENV{'HOME'}/scstats/scstats.db";
my $geo    = "$ENV{'HOME'}/scstats/GeoLiteCity.dat";
my $maxinc = 300; # maximum score difference between two datapoints to prevent arbitrary player scores set by some maps
my $debug  = 0;   # 1 prints debug output and won't use the DB

###

my ($dbh, $stats);

if (@ARGV != 1) {
   say "Usage: $0 <logfile>";
   exit;
}
elsif (! -f $ARGV[0] || ! -r $ARGV[0]) {
   say "$ARGV[0] is not a regular file or can't be read.";
   exit;
}

unless ($debug) {
   unless ($dbh = DBI->connect("DBI:SQLite:dbname=$db", '', '', { AutoCommit => 0 })) {
      say $DBI::errstr;
      exit;
   }

   my $sth = $dbh->prepare('SELECT steamid, name, id, score, lastscore, deaths, lastdeaths, joins, geo, lat, lon, datapoints FROM stats');
   $sth->execute;
   $stats = $sth->fetchall_hashref('steamid');
   $sth->finish;

   for (keys %{$stats}) {
      if (defined $$stats{$_}{score}) {
         $$stats{$_}{score}    = Math::BigFloat->new($$stats{$_}{score});
         $$stats{$_}{oldscore} = $$stats{$_}{score}->copy;
      }
      $$stats{$_}{olddeaths}     = $$stats{$_}{deaths}                         if(defined $$stats{$_}{deaths});
      $$stats{$_}{olddatapoints} = $$stats{$_}{datapoints}                     if(defined $$stats{$_}{datapoints});
      $$stats{$_}{lastscore}     = Math::BigFloat->new($$stats{$_}{lastscore}) if(defined $$stats{$_}{lastscore});
      $$stats{$_}{idx}           = $$stats{$_}{id}.'x'.$$stats{$_}{joins}      if(defined $$stats{$_}{id} && defined $$stats{$_}{joins});
   }
}

unless (open my $fh, '<', $ARGV[0]) { 
   die "opening file failed";
} 
else {
   while (my $in = <$fh>) {
      my $line = substr($in, 0, 2).substr($in, 25);
      chomp $line;
      say $line if($debug);

      if ($line =~ /^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><>" connected, address "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):/) {
         $$stats{$3}{name}  = $1;
         $$stats{$3}{id}    = $2;
         $$stats{$3}{ip}    = $4;
         $$stats{$3}{joins}++;
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

         if ($score->bcmp($$stats{$3}{lastscore})) {
            if (exists $$stats{$3}{idx} && $idx eq $$stats{$3}{idx}) {
               my $diff = $score->bsub($$stats{$3}{lastscore});
               $$stats{$3}{score}->badd($diff) unless($diff->babs > $maxinc);
               say "old: $$stats{$3}{lastscore} | diff: $diff | new: $$stats{$3}{score}" if($debug);
            }
            else {
               $$stats{$3}{score}->badd($score) unless($score->babs > $maxinc);
               say "old: $$stats{$3}{lastscore} | diff: $score | new: $$stats{$3}{score}" if($debug);
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
   close $fh; 
}

unless ($debug) {
   my $gi  = Geo::IP->open($geo, GEOIP_MEMORY_CACHE);
   my $sth = $dbh->prepare('REPLACE INTO stats (steamid64, steamid, name, id, score, lastscore, deaths, lastdeaths, scoregain, deathgain, joins, geo, lat, lon, datapoints, datapointgain) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');

   for (keys %{$stats}) {
      my ($country, $lat, $lon);

      if (defined $$stats{$_}{ip}) {
         my $record  = $gi->record_by_addr($$stats{$_}{ip});

         if ($record) {
            $country = $record->country_code3;
            $lat     = $record->latitude;
            $lon     = $record->longitude;
         }
      }

      $sth->execute(
         idto64($_),
         $_,
         defined $$stats{$_}{name}          ? $$stats{$_}{name}       : undef,
         defined $$stats{$_}{id}            ? $$stats{$_}{id}         : undef,
         defined $$stats{$_}{score}         ? $$stats{$_}{score}      : 0,
         defined $$stats{$_}{lastscore}     ? $$stats{$_}{lastscore}  : 0,
         defined $$stats{$_}{deaths}        ? $$stats{$_}{deaths}     : 0,
         defined $$stats{$_}{lastdeaths}    ? $$stats{$_}{lastdeaths} : 0,
         defined $$stats{$_}{oldscore}      ? $$stats{$_}{score}->copy->bsub($$stats{$_}{oldscore}) : 0,
         defined $$stats{$_}{olddeaths}     ? $$stats{$_}{deaths}-$$stats{$_}{olddeaths}            : 0,
         defined $$stats{$_}{joins}         ? $$stats{$_}{joins}      : 1,
         defined $country                   ? $country                : defined $$stats{$_}{geo} ? $$stats{$_}{geo} : undef,
         defined $lat                       ? $lat                    : defined $$stats{$_}{lat} ? $$stats{$_}{lat} : undef,
         defined $lon                       ? $lon                    : defined $$stats{$_}{lon} ? $$stats{$_}{lon} : undef,
         defined $$stats{$_}{datapoints}    ? $$stats{$_}{datapoints} : 0,
         defined $$stats{$_}{olddatapoints} ? $$stats{$_}{datapoints}-$$stats{$_}{olddatapoints}    : 0,
      );
   }

   $dbh->commit;
   $dbh->disconnect;
}
else {
   print Dumper(\%{$stats});
}

sub idto64 {
   my $id = shift || return 0;
   my (undef, $authbit, $accnum) = split(':', $id);
   my $id64 = (($accnum * 2) + 76561197960265728 + $authbit);
 
   return $id64;
}

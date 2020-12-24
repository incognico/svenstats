#!/usr/bin/env perl

# Sven Co-op (svends) log parser "svenstats.pl"
#
# Copyright 2016-2020, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.16.0;

use utf8; 
use strict; 
use warnings; 

use autodie;

no warnings 'experimental::smartmatch';

use DBI;
use MaxMind::DB::Reader;
use File::Slurp;
use File::Basename;

### config

my $db        = "$ENV{'HOME'}/scstats/scstats.db";
my $geo       = "$ENV{'HOME'}/gus/GeoLite2-City.mmdb";
my $maxinc    = 450; # maximum score difference between two datapoints to prevent arbitrary player scores set by some maps
my @blacklist = qw(ayakashi_banquet blackmesa_spacebasement bstore kbd2a runforfreedom_alpha1 skate_city trempler_weapons); # map blacklist, space seperated, lowercase

###

my $hold = 0;
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

unless ($dbh = DBI->connect("DBI:SQLite:dbname=$db", '', '', {AutoCommit => 1})) {
   say $DBI::errstr;
   exit;
}
$dbh->do('PRAGMA cache_size = -2000');
$dbh->do('PRAGMA journal_mode = MEMORY');
$dbh->do('PRAGMA synchronous = OFF');
$dbh->{AutoCommit} = 0;

my %ids;
my @lines2;
my $re = qr'^L ".+<[0-9]+><STEAM_(0:[01]:[0-9]+)><';

while (my $in = shift(@lines)) {
   next if (length($in) < 28);

   my $line = substr($in, 0, 2).substr($in, 25);

   push(@lines2, $line);

   $ids{idto64($1)}++ if ($line =~ $re);
}

exit unless (keys %ids > 0);

my $where = 'steamid64 IN (';
$where .= $_ . ',' foreach (keys %ids);
$where = substr($where, 0, -1) . ')';

$stats = $dbh->selectall_hashref('SELECT steamid, name, id, score, lastscore, deaths, lastdeaths, joins, geo, lat, lon, datapoints, seen FROM stats WHERE ' . $where, 'steamid');

for (keys %{$stats}) {
   $$stats{$_}{oldscore}      = $$stats{$_}{score}                     if(defined $$stats{$_}{score});
   $$stats{$_}{olddeaths}     = $$stats{$_}{deaths}                    if(defined $$stats{$_}{deaths});
   $$stats{$_}{olddatapoints} = $$stats{$_}{datapoints}                if(defined $$stats{$_}{datapoints});
   $$stats{$_}{lastscore}     = $$stats{$_}{lastscore}                 if(defined $$stats{$_}{lastscore});
   $$stats{$_}{idx}           = $$stats{$_}{id}.'x'.$$stats{$_}{joins} if(defined $$stats{$_}{id} && defined $$stats{$_}{joins});
}

$maps = $dbh->selectall_hashref('SELECT map, count FROM maps', 'map');

my $res = $dbh->selectrow_hashref('SELECT hold FROM misc WHERE rowid = 1');
$hold = $$res{hold} if(defined $$res{hold});

my $addr_re = qr'^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><>" connected, address "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):';
my $entr_re = qr'^L ".+<[0-9]+><STEAM_(0:[01]:[0-9]+)><players?>" has entered the game';
my $stat_re = qr'^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><players?>" stats: frags="(-?[0-9]+\.[0-9]{2})" deaths="([0-9]+)"';
my $blck_re = qr'^L Started map "(.+)" \(CRC "-?[0-9]+"\)';

while (my $line = shift(@lines2)) {
   if ($line =~ $blck_re) {
      if (lc($1) ~~ @blacklist) {
         $hold = 1;
      }
      else {
         $hold = 0;
      }

      $$maps{lc($1)}{count}++;
   }

   if ($line =~ $addr_re) {
      $$stats{$3}{name} = $1;
      $$stats{$3}{id}   = $2;
      $$stats{$3}{ip}   = $4;
      $$stats{$3}{joins}++;
   }
   elsif ($line =~ $entr_re) {
      $$stats{$1}{joins}++;
      $$stats{$1}{wasseen} = 1;
   }
   elsif ($line =~ $stat_re) {
      $$stats{$3}{score}      = 0 unless(defined $$stats{$3}{score});
      $$stats{$3}{lastscore}  = 0 unless(defined $$stats{$3}{lastscore});
      $$stats{$3}{deaths}     = 0 unless(defined $$stats{$3}{deaths});
      $$stats{$3}{lastdeaths} = 0 unless(defined $$stats{$3}{lastdeaths});

      my $score = $4;
      my $idx   = $2.'x'.(defined $$stats{$3}{joins} ? $$stats{$3}{joins} : 1);
      
      unless ($hold) {
         if (abs($score) <=> abs($$stats{$3}{lastscore})) {
            if (exists $$stats{$3}{idx} && $idx eq $$stats{$3}{idx}) {
               my $diff = $score - $$stats{$3}{lastscore};
               $$stats{$3}{score} += $diff unless(abs($diff) > $maxinc);
            }
            else {
               $$stats{$3}{score} += $score unless(abs($score) > $maxinc);
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
      }

      $$stats{$3}{name}       = $1;
      $$stats{$3}{id}         = $2;
      $$stats{$3}{idx}        = $idx;
      $$stats{$3}{lastscore}  = $4;
      $$stats{$3}{lastdeaths} = $5;
      $$stats{$3}{datapoints}++;
      $$stats{$3}{wasseen}    = 1;
   }
}

my $gi  = MaxMind::DB::Reader->new(file => $geo);
my $sth = $dbh->prepare('REPLACE INTO stats (steamid64, steamid, name, id, score, lastscore, deaths, lastdeaths, scoregain, deathgain, joins, geo, lat, lon, datapoints, datapointgain, seen) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');

for (keys %{$stats}) {
   my ($country, $lat, $lon);

   if (defined $$stats{$_}{ip}) {
      my $record  = $gi->record_for_address($$stats{$_}{ip});

      if ($record) {
         $country = $record->{country}{iso_code};
         $lat     = $record->{location}{latitude};
         $lon     = $record->{location}{longitude};
      }
   }

   $sth->execute(
      idto64($_),
      $_,
      defined $$stats{$_}{name}          ? $$stats{$_}{name}       : undef,
      defined $$stats{$_}{id}            ? $$stats{$_}{id}         : undef,
      defined $$stats{$_}{score}         ? sprintf('%.2f', $$stats{$_}{score})     : 0,
      defined $$stats{$_}{lastscore}     ? sprintf('%.2f', $$stats{$_}{lastscore}) : 0,
      defined $$stats{$_}{deaths}        ? $$stats{$_}{deaths}     : 0,
      defined $$stats{$_}{lastdeaths}    ? $$stats{$_}{lastdeaths} : 0,
      defined $$stats{$_}{oldscore}      ? sprintf('%.2f', $$stats{$_}{score}-$$stats{$_}{oldscore}) : 0,
      defined $$stats{$_}{olddeaths}     ? $$stats{$_}{deaths}-$$stats{$_}{olddeaths} : 0,
      defined $$stats{$_}{joins}         ? $$stats{$_}{joins}      : 1,
      defined $country                   ? $country                : defined $$stats{$_}{geo}  ? $$stats{$_}{geo}  : undef,
      defined $lat                       ? $lat                    : defined $$stats{$_}{lat}  ? $$stats{$_}{lat}  : undef,
      defined $lon                       ? $lon                    : defined $$stats{$_}{lon}  ? $$stats{$_}{lon}  : undef,
      defined $$stats{$_}{datapoints}    ? $$stats{$_}{datapoints} : 0,
      defined $$stats{$_}{olddatapoints} ? $$stats{$_}{datapoints}-$$stats{$_}{olddatapoints}  : 0,
      defined $$stats{$_}{wasseen}       ? $today                  : defined $$stats{$_}{seen} ? $$stats{$_}{seen} : undef
   );
}
$dbh->commit;

$sth = $dbh->prepare('UPDATE stats SET lastscore = 0, lastdeaths = 0, scoregain = 0, deathgain = 0, datapointgain = 0 WHERE seen != ?');
$sth->execute($today);
$dbh->commit;

$sth = $dbh->prepare('REPLACE INTO maps (map, count) VALUES (?,?)');

for (keys %{$maps}) {
   $sth->execute($_, $$maps{$_}{count});
}
$dbh->commit;

$sth = $dbh->prepare('REPLACE INTO misc (rowid, hold) VALUES (1,?)');
$sth->execute($hold);
$dbh->commit;

$dbh->{AutoCommit} = 1;
$dbh->do('PRAGMA optimize');
$dbh->do('VACUUM') if ($today =~ /20[0-9]{2}-[0-9]{2}-01/);

$dbh->disconnect;

###

sub idto64 {
   my $id = shift || return 0;
   my (undef, $authbit, $accnum) = split(':', $id);
   my $id64 = (($accnum * 2) + 76561197960265728 + $authbit);
 
   return $id64;
}

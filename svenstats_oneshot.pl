#!/usr/bin/env perl

# Sven Co-op (svends) log parser "svenstats_oneshot.pl - Top players -> discord webhook"
#
# Copyright 2016-2021, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.20.0;

use utf8; 
use strict; 
use warnings; 
use autodie ':all';

use feature 'signatures';
no warnings qw(experimental::signatures experimental::smartmatch);

use Encode::Simple qw(decode_utf8_lax);
use File::Basename;
use File::Slurp;
use JSON::MaybeXS;
use LWP::UserAgent;
use MaxMind::DB::Reader;
use POSIX 'floor';

### config

my $maxinc   = 65534; # maximum score difference between two datapoints to prevent arbitrary player scores set by some maps
my $url      = 'https://discordapp.com/api/webhooks/...';
my $num      = 25;
my $inline   = 0;
my $steam    = 0;
my $steamkey = '';
my $geo      = "$ENV{'HOME'}/gus/GeoLite2-City.mmdb";
#my $discord_markdown_pattern = qr/(?<!\\)(`|@|:|#|\||__|\*|~|>)/;
my $discord_markdown_pattern = qr/(?<!\\)(`|@|#|\||_|\*|~|>)/;

###

if (@ARGV != 1) {
   say "Usage: $0 <logfile>";
   exit;
}
elsif (! -f $ARGV[0] || ! -r $ARGV[0]) {
   say "$ARGV[0] is not a regular file or can't be read.";
   exit;
}

my ($stats, $alldatapoints) = ({}, 0);
my $today = fileparse( $ARGV[0], qw(.log) );
my @lines = read_file( $ARGV[0], binmode => ':raw', chomp => 1 ) ;

for my $in (@lines) {
   next if (length($in) < 28);

   my $line = decode_utf8_lax(substr($in, 0, 2).substr($in, 25));

   if ($line =~ /^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><>" connected, address "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):/) {
      $$stats{$3}{name} = $1;
      $$stats{$3}{id}   = $2;
      $$stats{$3}{ip}   = $4;
      $$stats{$3}{joins}++;
      $$stats{$3}{datapoints} = 0 unless(defined $$stats{$3}{datapoints});
   }
   elsif ($line =~ /^L ".+<[0-9]+><STEAM_(0:[01]:[0-9]+)><players?>" has entered the game/) {
      $$stats{$1}{joins}++;
   }
   elsif ($line =~ /^L "(.+)<([0-9]+)><STEAM_(0:[01]:[0-9]+)><[a-z_-]+>" stats: frags="(-?[0-9]+\.[0-9]{2})" deaths="([0-9]+)"/) {
      $$stats{$3}{score}      = 0 unless(defined $$stats{$3}{score});
      $$stats{$3}{lastscore}  = 0 unless(defined $$stats{$3}{lastscore});
      $$stats{$3}{deaths}     = 0 unless(defined $$stats{$3}{deaths});
      $$stats{$3}{lastdeaths} = 0 unless(defined $$stats{$3}{lastdeaths});

      my $score = $4;
      my $idx   = $2.'x'.(defined $$stats{$3}{joins} ? $$stats{$3}{joins} : 1);
      
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

      $$stats{$3}{name}       = $1;
      $$stats{$3}{id}         = $2;
      $$stats{$3}{idx}        = $idx;
      $$stats{$3}{lastscore}  = $4;
      $$stats{$3}{lastdeaths} = $5;
      $$stats{$3}{datapoints}++;
      $alldatapoints++;
   }
}

my $msg = {
   'content' => '',
   'embeds' => [
      {
         'color' => randcol(),
         'footer' => {
            'text' => $today . ' - Unique players: ' . (scalar keys $stats->%*) . ' - Combined playtime: ' . duration($alldatapoints*30),
         },
      },
   ],
};

my $gi = MaxMind::DB::Reader->new(file => $geo);
my ($n, $c) = (0, 0);

foreach my $key (sort { $$stats{$b}{datapoints} <=> $$stats{$a}{datapoints} } keys %{$stats}) {
   if ($$stats{$key}{datapoints} > 10) {
      if (defined $$stats{$key}{ip}) {
         my $country;

         my $record  = $gi->record_for_address($$stats{$key}{ip});
         $country = lc($record->{country}{iso_code}) if($record);

         push @{$$msg{'embeds'}[0]{'fields'}}, { 'name' => sprintf(":flag_%s: **%s**", defined $country ? $country : 'white', discord($$stats{$key}{name})), 'value' => sprintf("#**%s** Playtime: **%s** Score: **%s** Deaths: **%s**", $n+1, duration($$stats{$key}{datapoints}*30), int($$stats{$key}{score}), $$stats{$key}{deaths}), 'inline' => \$inline, 'steamid64' => idto64($key) };

         $n++;
      }
   }

   $c++; last if ($c >= $num);
}

exit unless ($n > 0);
my $rc = @{$$msg{'embeds'}[0]{'fields'}};
$$msg{'embeds'}[0]{'title'} = ":trophy: Top $rc players in the last 24h";

my $ua = LWP::UserAgent->new;
$ua->agent( 'Mozilla/5.0' );
my $r;

if ($steam) {
   my ($steamres, %steamdata);

   $r = $ua->get( "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=$steamkey&steamids=" . join(',', map $_->{steamid64}, @{$$msg{'embeds'}[0]{'fields'}}) );
   $r->is_success ? $steamres = decode_json( $r->decoded_content ) : return;
   @steamdata{map $_->{steamid}, @{$$steamres{response}{players}}} = @{$$steamres{response}{players}};

   if ($steamres) {
      for (@{$$msg{'embeds'}[0]{'fields'}}) {
         $_->{value} .= " Steam: **[" . discord($steamdata{$_->{steamid64}}{personaname}) . "]($steamdata{$_->{steamid64}}{profileurl})**";
         delete ($_->{steamid64});
      }
   }
}

$r = HTTP::Request->new( 'POST', $url );
$r->content_type( 'application/json' );
$r->content( encode_json( $msg ) );
$ua->request( $r );

###

sub discord ($string = '') {
   $string =~ s/$discord_markdown_pattern/\\$1/g;

   return $string;
}

sub duration ($sec = 0) {
   return '?' unless ($sec);

   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                                       $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '');
}

sub idto64 ($id) {
   my (undef, $authbit, $accnum) = split(':', $id);
   my $id64 = (($accnum * 2) + 76561197960265728 + $authbit);

   return $id64;
}

sub randcol () {
   my ($h, $s, $v) = (rand(360)/60, 0.5+rand(0.5), 0.9+rand(0.1));

   my $i = floor( $h );
   my $f = $h - $i;
   my $p = $v * ( 1 - $s );
   my $q = $v * ( 1 - $s * $f );
   my $t = $v * ( 1 - $s * ( 1 - $f ) );

   my ($r, $g, $b);

   if ( $i == 0 ) {
      ($r, $g, $b) = ($v, $t, $p);
   }
   elsif ( $i == 1 ) {
      ($r, $g, $b) = ($q, $v, $p);
   }
   elsif ( $i == 2 ) {
      ($r, $g, $b) = ($p, $v, $t);
   }
   elsif ( $i == 3 ) {
      ($r, $g, $b) = ($p, $q, $v);
   }
   elsif ( $i == 4 ) {
      ($r, $g, $b) = ($t, $p, $v);
   }
   else {
      ($r, $g, $b) = ($v, $p, $q);
   }

   return hex(sprintf('0x%02x%02x%02x', int(floor($r*255)), int(floor($g*255)), int(floor($b*255))));
}

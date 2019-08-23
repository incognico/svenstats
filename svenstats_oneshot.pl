#!/usr/bin/env perl

# Sven Co-op (svends) log parser "svenstats_oneshot.pl - Top players -> discord webhook"
#
# Copyright 2016-2019, Nico R. Wohlgemuth <nico@lifeisabug.com>

use 5.16.0;

use utf8; 
use strict; 
use warnings; 

use autodie;

no warnings 'experimental::smartmatch';

use MaxMind::DB::Reader;
use Math::BigFloat;
use File::Slurp;
use File::Basename;
use LWP::UserAgent;
use JSON;
use Encode;

### config

my $geo = '/usr/share/GeoIP/GeoLite2-City.mmdb';
my $url = '';
my $inline = \0; # \0 or \1
my $num = 25;
my @colors = qw(1752220 3066993 3447003 10181046 15844367 15105570 15158332 9807270 8359053 3426654 1146986 2067276 2123412 7419530 12745742 11027200 10038562 9936031 12370112 2899536);

###

sub duration {
   my $sec = shift;

   return '?' unless ($sec);

   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                                       $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '');
#            ($gmt[0] ? ($gmt[5] || $gmt[7] || $gmt[2] || $gmt[1] ? ' ' : '').$gmt[0].'s' : '');
}

my $stats;

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

   my $line = Encode::decode_utf8(substr($in, 0, 2).substr($in, 25));

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
my $uniq = keys %{$stats};
my $c = 0;

my $msg = {
   'content' => '',
   'embeds' => [
      {
         'color' => $colors[rand @colors],
         'footer' => {
            'text' => "$today - Unique players: $uniq",
         },
      },
   ],
};

foreach my $key (sort { $$stats{$b}{datapoints} <=> $$stats{$a}{datapoints} } keys %{$stats}) {
   my ($country, $lat, $lon);

   if ($$stats{$key}{datapoints} > 10) {
      if (defined $$stats{$key}{ip}) {
         my $record  = $gi->record_for_address($$stats{$key}{ip});

         if ($record) {
            $country = lc($record->{country}{iso_code});
         }
      }

      push @{$$msg{'embeds'}[0]{'fields'}}, { 'name' => sprintf(":flag_%s: %s", defined $country ? $country : 'white', $$stats{$key}{name}), 'value' => sprintf("#**%s**  Playtime: **%s** Score: **%s** Deaths: **%s**", $c+1, duration($$stats{$key}{datapoints}*30), int($$stats{$key}{score}), $$stats{$key}{deaths}), 'inline' => $inline };
   }

   $c++;
   last if ($c >= $num);
}

my $rc = @{$$msg{'embeds'}[0]{'fields'}};
$$msg{'embeds'}[0]{'title'} = ":trophy: Top $rc players in the last 24h";

my $r = HTTP::Request->new( 'POST', $url );
$r->content_type( 'application/json' );
$r->content( encode_json( $msg ) );

my $ua = LWP::UserAgent->new;
$ua->agent( 'Mozilla/5.0' );
$ua->request( $r );

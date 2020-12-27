#!/bin/bash

bin="/home/svends/scstats/svenstats.pl"
db="/home/svends/scstats/scstats.db"
schema="/home/svends/scstats/schema.sqlite"
logp="/home/svends/scstats/logs"

[[ -f "$db" ]] && { echo "db exists"; exit; }

sqlite3 "$db" < "$schema"

for i in "$logp"/*.gz
do
   tmp=/tmp/$(basename $i .gz)
   echo "processing: $tmp"
   zcat $i > $tmp
   $bin $tmp
   rm $tmp
done

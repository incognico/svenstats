#!/bin/bash

# Cronjob script for svenstats.pl
# SvenDS logs are rotated at 00:00
# Example crontab entry to copy the log from yesterday to $statslogpath and generate stats from it at 00:05:
# 5 0 * * * /bin/bash /path/to/this/script/svenstats_cronjob.bash

#  Yesterday:
#     FreeBSD:   date -v-1d "+%Y-%m-%d"
#     GNU/Linux: date --date='1 day ago' "+%Y-%m-%d"

yesterday=$(date --date='1 day ago' "+%Y-%m-%d")
svenstats="/home/srcds/scstats/svenstats.pl"
svenstatsdb="/home/srcds/scstats/scstats.db"
svenlogpath="/home/srcds/sc5/svencoop/logs"
statslogpath="/home/srcds/scstats/logs"
#twlzstatsfile="/home/srcds/sc5/svencoop_addon/scripts/plugins/twlzstats.txt"
#hldschat="/home/srcds/scstats/hldschat.pl"
#chatlogpath="/home/srcds/sc5/svencoop_addon/chatlogs"

cp "${svenlogpath}/${yesterday}.log" "${statslogpath}/${yesterday}.log"
$svenstats "${statslogpath}/${yesterday}.log"
#$hldschat "${statslogpath}/${yesterday}.log" >> "${chatlogpath}/${yesterday}.html"

gzip "${statslogpath}/${yesterday}.log"

if [ -f "${statslogpath}/${yesterday}.log.gz" ]; then
  rm "${statslogpath}/${yesterday}.log"
fi

#sqlite3 -list -separator ' ' $svenstatsdb 'select steamid,cast(score + 0.5 as int),deaths from stats where score >2500 order by score desc' | cat -n | sed -e "s/[[:space:]]\+/ /g" | cut -c 2- > $twlzstatsfile

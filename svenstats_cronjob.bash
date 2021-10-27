#!/bin/bash

# Cronjob script for svenstats.pl
# SvenDS logs are rotated at 00:00
# Example crontab entry to copy the log from yesterday to $statslogpath and generate stats from it at 00:05:
# 5 0 * * * /bin/bash /path/to/this/script/svenstats_cronjob.bash

#  Yesterday (actually exactly 24h ago, which does work for forward DST changes so we just use 12 hours ago):
#     FreeBSD:   date -v-1d "+%Y-%m-%d"
#     GNU/Linux: date --date='1 day ago' "+%Y-%m-%d"

yesterday=$(date --date='12 hours ago' "+%Y-%m-%d")
svenstats="/home/svends/scstats/svenstats.pl"
svenstatsos="/home/svends/scstats/svenstats_oneshot.pl"
svenstatsdb="/home/svends/scstats/scstats.db"
svenlogpath="/home/svends/sc5/svencoop/logs"
statslogpath="/home/svends/scstats/logs"
#twlzstatsfile="/home/svends/sc5/svencoop_addon/scripts/plugins/cfg/twlzstats.txt"
#hldschat="/home/srcds/scstats/hldschat.pl"
#chatlogpath="/home/srcds/sc5/svencoop_addon/chatlogs"

mv "${svenlogpath}/${yesterday}.log" "${statslogpath}/${yesterday}.log"
$svenstatsos "${statslogpath}/${yesterday}.log"
$svenstats "${statslogpath}/${yesterday}.log"
#$hldschat "${statslogpath}/${yesterday}.log" >> "${chatlogpath}/${yesterday}.html"

xz "${statslogpath}/${yesterday}.log"

#sqlite3 -list -separator ' ' $svenstatsdb 'select steamid,cast(score + 0.5 as int),deaths from stats where score >5000 order by score desc' | cat -n | sed -e "s/[[:space:]]\+/ /g" | cut -c 2- > $twlzstatsfile

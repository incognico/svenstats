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
svenlogpath="/home/srcds/sc5/svencoop/logs"
statslogpath="/home/srcds/scstats/logs"

cp "${svenlogpath}/${yesterday}.log" "${statslogpath}/${yesterday}.log"
$svenstats "${statslogpath}/${yesterday}.log"

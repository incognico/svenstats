## svenstats.pl for Sven Co-op servers (SvenDS)
Log parser for Sven Co-op dedicated servers (SvenDS) logs, to gather player statistics (name, score, deaths, country, etc.).

## Notes
* Assumes default SvenDS log settings (log file rotation every 24h)
* sv_log_player_frequency should be consistent for every log file to calculate playtime from the 'datapoints' value
* Score differences achived by players before a map ends may be lost for up to a maximum of the sv_log_player_frequency value (seconds). This is due to the nature of how the logging works and thus the gathered stats are not 100% accurate, but still good enough :)
* 'joins' are not acual joins, merely a hack to get a better session id ('idx')

## Requirements
* SvenDS log files
* Perl >=5.16
  * Data::Dumper (for $debug = 1)
  * Geo::IP (and [GeoCityLite.dat](https://dev.maxmind.com/geoip/legacy/geolite/))
  * DBI
  * DBD::SQLite
* SQLite 3

## Get started
1. ```sqlite3 scstats.db < schema.sqlite```
2. Configure ```$db``` and ```$geo``` in ```svenstats.pl```
3. Optional: Feed it with old logs (but the current one!) ```for i in /path/to/logs/excluding/the/current/one/*.log ; do svenstats.pl $i ; done```
4. Add a daily cronjob which feeds yesterdays closed log to ```svenstats.pl``` (example file: ```svenstats_cronjob.bash```)
5. Do cool stuff with the gathered data, example: [twlz.lifeisabug.com](http://twlz.lifeisabug.com/)

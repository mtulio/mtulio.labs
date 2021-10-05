# *nix command: Find

## mtime

* Find files older than 2 days:

`find /path/to/files* -mtime +2`

* Find and remove all files (including dirs) older than 2 days:

`find /path/to/files* -mtime +2 -exec rm -rf {}\;`

* Find and remove all files (only) older than 2 days:

`find /path/to/files* -mtime +2 -type f -exec rm -rf {}\;`

* Find files bigger than 50M

`find /tmp -type f -size +50M`

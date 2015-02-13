Raid and Controller check
raid_check
=========================

Bash script for parse output from next utilits and return raid and controller status:

* `hpacucli`
* `MegaCli`
* `StorMan`
* `mpt-status`
* `sas2ircu`

Used for monitoring systems:  Zabbix Nagios NetXMS end etc.

Ussage:
```bash
./raid_check.sh RAID_STATUS
```
or
```bash
./raid_check.sh CTRL_STATUS
```
PS

Before get status, you must call
```bash
./raid_check.sh GET_TMP_REPORT
```

for write output from utilite to temp file.

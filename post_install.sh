#!/bin/sh -x
# Enable the service
sysrc apache24_enable="YES"
sysrc asterisk_enable="YES"
sysrc asterisk_user=$ASTERISK_USER
sysrc asterisk_group=$ASTERISK_USER
sysrc mysql_enable="YES"
sysrc mysql_args="--character-set-server=utf8"

#!/bin/sh -x
FREEPBX_VER="freepbx-15.0-latest.tgz"

MYSQL_ROOT_PASS=$(openssl rand -base64 20 | md5 | head -c20)

MY_SERVER_NAME=$(hostname)
IP_ADDRESS=$(ifconfig | grep -E 'inet.[0-9]' | grep -v '127.0.0.1' | awk '{ print $2}')

ASTERISK_USER="asterisk"

# Enable the service
sysrc apache24_enable="YES"
sysrc asterisk_enable="YES"
sysrc asterisk_user=$ASTERISK_USER
sysrc asterisk_group=$ASTERISK_USER
sysrc mysql_enable="YES"
sysrc mysql_args="--character-set-server=utf8"


#####################
# Linux compatablity
#####################
mkdir /home/asterisk
chown asterisk:asterisk /home/asterisk
pw usermod asterisk -d /home/asterisk/ -m
chsh -s /usr/local/bin/bash asterisk

#!/bin/sh -x
FREEPBX_VER="freepbx-15.0-latest.tgz"

MYSQL_ROOT_PASS=$(openssl rand -base64 20 | md5 | head -c20)

MY_SERVER_NAME=$(hostname)
IP_ADDRESS=$(ifconfig | grep -E 'inet.[0-9]' | grep -v '127.0.0.1' | awk '{print $2}')

ASTERISK_USER="asterisk"

# Enable the service
sysrc apache24_enable="YES"
sysrc asterisk_enable="YES"
sysrc asterisk_user=$ASTERISK_USER
sysrc asterisk_group=$ASTERISK_USER
sysrc mysql_enable="YES"
sysrc mysql_args="--character-set-server=utf8"

pear install Console_Getopt

#####################
# Linux compatablity
#####################
mkdir /home/asterisk
chown asterisk:asterisk /home/asterisk
pw usermod asterisk -d /home/asterisk/ -m
chsh -s /usr/local/bin/bash asterisk
  
#simple script to take the runuser command that FreePBX uses and turn it in to su command.
cat > /usr/local/bin/runuser <<EOF
#!/bin/sh
su \$1 \$4 "\$5"
EOF

chmod 655 /usr/local/bin/runuser

sed -i.bak 's/\[directories\](\!)/[directories]/' /usr/local/etc/asterisk/asterisk.conf

#############
# mysql
#############
cat > /usr/local/etc/odbc.ini <<EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
driver=MySQL
server=localhost
database=asteriskcdrdb
Port=3306
option=3
Charset=utf8
EOF

cat > /usr/local/etc/odbcinst.ini <<EOF
[MySQL]
Description=ODBC for MySQL
Driver=/usr/local/lib/libmyodbc5w.so
UsageCount=20003
EOF

##############
# apache
##############
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini
sed -i.bak 's/\(^upload_max_filesize = \).*/\120M/' /usr/local/etc/php.ini
sed -i.bak 's/\(^memory_limit = \).*/\1256M/' /usr/local/etc/php.ini

cp /usr/local/etc/apache24/httpd.conf /usr/local/etc/apache24/httpd.conf_orig
sed -i.bak -E "s/^(User|Group).*/\1 ${ASTERISK_USER}/" /usr/local/etc/apache24/httpd.conf
sed -i.bak 's/AllowOverride None/AllowOverride All/' /usr/local/etc/apache24/httpd.conf
  
sed -i.bak '/^#LoadModule rewrite_module libexec\/apache24\/mod_rewrite.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
sed -i.bak '/^#LoadModule mime_magic_module libexec\/apache24\/mod_mime_magic.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
  
sed -i.bak '/AddType application\/x-httpd-php .php/d' /usr/local/etc/apache24/httpd.conf
  
sed -i.bak '/\<IfModule mime_module\>/a\
    AddType application/x-httpd-php .php
    ' /usr/local/etc/apache24/httpd.conf
    
sed -i.bak 's/DirectoryIndex index.html/DirectoryIndex index.php index.html/' /usr/local/etc/apache24/httpd.conf
    
# apache config ssl
sed -i.bak '/^#LoadModule ssl_module libexec\/apache24\/mod_ssl.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
  
mkdir -p /usr/local/etc/apache24/ssl
cd /usr/local/etc/apache24/ssl

#The line bellow had issues in freebsd 12, /root/.rnd file is missing on freebsd 12?
#openssl genrsa -rand -genkey -out private.key 2048
#Replacement line
openssl genrsa -out private.key 2048
  
openssl req -new -x509 -days 365 -key private.key -out certificate.crt -sha256 -subj "/C=CA/ST=ONTARIO/L=TORONTO/O=Global Security/OU=IT Department/CN=${MY_SERVER_NAME}"
  
cat > /usr/local/etc/apache24/modules.d/020_mod_ssl.conf <<EOF
Listen 443
SSLProtocol ALL -SSLv2 -SSLv3
SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5
SSLPassPhraseDialog builtin
SSLSessionCacheTimeout 300
EOF
        
cat > /usr/local/etc/apache24/Includes/freepbx.conf <<EOF
<VirtualHost *:80>
  ServerName $MY_SERVER_NAME
  
  DocumentRoot /usr/local/www/freepbx/admin
  <Directory "/usr/local/www/freepbx/admin">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>

<VirtualHost *:443>
  ServerName $MY_SERVER_NAME
  
  SSLEngine on
  SSLCertificateFile "/usr/local/etc/apache24/ssl/certificate.crt"
  SSLCertificateKeyFile "/usr/local/etc/apache24/ssl/private.key"
  DocumentRoot /usr/local/www/freepbx/admin
  <Directory "/usr/local/www/freepbx/admin">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

###############
# start service
###############
service asterisk restart
service mysql-server restart

###############
# MySQL setup
###############
MYSQL_PASS=$(tail -1 /root/.mysql_secret)

mysql -uroot -p"$MYSQL_PASS" -e "SET PASSWORD FOR root@'localhost' = PASSWORD('$MYSQL_ROOT_PASS');" --connect-expired-password

mysql -uroot -p"$MYSQL_ROOT_PASS" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

#mysql_secure_installation <<EOF
#
#y
#$MYSQL_ROOT_PASS
#$MYSQL_ROOT_PASS
#y
#y
#y
#y
#EOF

mysqladmin -u root -p$MYSQL_ROOT_PASS password ''

###############
# FreePBX
###############
mkdir -p /usr/src
cd /usr/src

MIRROR="mirror"
while [ ! -f "$FREEPBX_VER" ]
do
  URL=http://$MIRROR.freepbx.org/modules/packages/freepbx/$FREEPBX_VER
  fetch http://$MIRROR.freepbx.org/modules/packages/freepbx/$FREEPBX_VER
  sleep 1
  case "$MIRROR" in
    mirror)
      MIRROR="mirror1"
        ;;
    mirror1)
      MIRROR="mirror2"
        ;;
    *)
      MIRROR="mirror"
        ;;
  esac      
done
rm -R freepbx
tar vxfz $FREEPBX_VER
    
cd freepbx
touch /usr/local/etc/asterisk/{modules,ari,statsd}.conf
./install -n

###############
# post install
###############
chown asterisk:asterisk /usr/local/etc/asterisk/*

ln -s /usr/local/freepbx/sbin/fwconsole /usr/local/sbin/fwconsole
#sed -i.bak -E 's/(:path=\/sbin \/bin \/usr\/sbin \/usr\/bin \/usr\/local\/sbin \/usr\/local\/bin ~\/bin).*/\1 \/usr\/local\/freepbx\/sbin \/usr\/local\/freepbx\/bin:\\/' /etc/login.conf

mysqladmin -u root password '$MYSQL_ROOT_PASS'

/usr/local/freepbx/bin/fwconsole ma disablerepo commercial
/usr/local/freepbx/bin/fwconsole ma installall
/usr/local/freepbx/bin/fwconsole ma delete firewall
/usr/local/freepbx/bin/fwconsole ma delete xmpp
/usr/local/freepbx/bin/fwconsole reload
  
/usr/local/freepbx/bin/fwconsole set CERTKEYLOC /usr/local/etc/asterisk/keys
#/usr/local/freepbx/bin/fwconsole reload
/usr/local/freepbx/bin/fwconsole restart

service apache24 restart

echo -e "FreePBX 15 now installed." > /root/PLUGIN_INFO
echo -e "     Your MySQL Root password is \"${MYSQL_ROOT_PASS}\"." >> /root/PLUGIN_INFO

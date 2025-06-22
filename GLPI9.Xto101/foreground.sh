#!/bin/bash

# turn on bash's job control
set -m

#######
# clean old pid and "fix" cron
find /var/run/ -type f -iname \*.pid -delete
touch /etc/crontab /etc/cron.d/glpi

#######
# timezone
if test -v TZ && [ `readlink /etc/localtime` != "/usr/share/zoneinfo/$TZ" ]; then
  if [ -f /usr/share/zoneinfo/$TZ ]; then
    echo $TZ > /etc/timezone 
    rm /etc/localtime 
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime 
    dpkg-reconfigure -f noninteractive tzdata 

    echo "date.timezone=$TZ" > /etc/php/7.3/apache2/conf.d/99_timezone.ini 
  fi
fi

# disable LDAP valid TLS cert
if test -v GLPI_TLSNEVER; then
    echo "TLS_REQCERT   never" >> /etc/ldap/ldap.conf
fi

###################
# GLPI directories
DIRGLPI=/var/www/html/glpi

# Create required directories
for dir in _cache _cron _dumps _graphs _lock _log _pictures _plugins _rss _sessions _tmp _uploads
do
    mkdir -p $DIRGLPI/files/$dir
done

# Set permissions
chown -R www-data:www-data $DIRGLPI/files
chmod -R 755 $DIRGLPI/files

# If GLPI is already installed, rename install.php
if test -v GLPI_INSTALLED; then
   [ -f $DIRGLPI/install/install.php ] && mv $DIRGLPI/install/install.php $DIRGLPI/install/install.php.old
fi

# Configure database if environment variables are set
if test -v GLPI_DATABASE_HOST; then
  
echo "<?php
class DB extends DBmysql {
   public \$dbhost     = '$GLPI_DATABASE_HOST';
   public \$dbuser     = '$GLPI_DATABASE_USER';
   public \$dbpassword = '$GLPI_DATABASE_PASS';
   public \$dbdefault  = '$GLPI_DATABASE_NAME';
}" > $DIRGLPI/config/config_db.php

chown www-data:www-data $DIRGLPI/config/config_db.php
chmod 600 $DIRGLPI/config/config_db.php

fi

###################
# Start cron
/usr/sbin/cron

# Start Apache
source /etc/apache2/envvars
exec apache2 -D FOREGROUND

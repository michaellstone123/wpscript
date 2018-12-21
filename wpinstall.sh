#!/bin/bash

RED='\033[1;31m'   # Red
NC='\033[0m'       # No Color
GREEN='\033[1;32m' # Green

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

domain=$1
sitesEnabled='/etc/apache2/sites-enabled/'
sitesAvailable='/etc/apache2/sites-available/'

while [ "${domain}" = "" ]
do
    echo -e "${GREEN}Please provide domain:${NC}"
    read domain
done

#####Soft installation
apt-get update
apt-get install -y software-properties-common
apt-get install -y nano curl
echo -e "${GREEN}Installing Apache2${NC}"
apt-get install -y apache2
a2enmod expires && a2enmod rewrite && a2enmod headers && a2enmod ssl
echo -e "${GREEN}Installing MySQL${NC}"
debconf-set-selections <<< 'mysql-server mysql-server/root_password password dbrootpass001'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password dbrootpass001'
apt-get -y install mysql-server
echo -e "${GREEN}Installing PHP${NC}"
apt-get install -y php libapache2-mod-php php-mcrypt php-mysql php-zip php-curl php-gd php-mbstring php-xml php-xmlrpc
#Modify disposition by index files
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 64M/" /etc/php/7.0/apache2/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 64M/" /etc/php/7.0/apache2/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/7.0/apache2/php.ini
sed -i "s/DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/" /etc/apache2/mods-available/dir.conf
echo -e "${GREEN}Restarting Apache2${NC}"
/etc/init.d/apache2 restart
#####VHOST
#Modify apache2 config
printf "<Directory /var/www/html/>\nAllowOverride All\n</Directory>" >> /etc/apache2/apache2.conf
sed -i "s/ServerName localhost/ServerName ${domain}/" /etc/apache2/apache2.conf
#Apache2 restart
/etc/init.d/apache2 restart

echo -e "${GREEN}Complete! You now have a new Virtual Host. Your new host is: http://${domain}${NC}"

##### WordPress instalation
#Create MySQL database
rootpass='dbrootpass001'
read -p "Database name: " dbname
read -p "Database username: " dbuser
read -p "Enter a password for user ${dbuser}: " userpass
echo "CREATE DATABASE ${dbname} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;" | mysql -u root -p${rootpass}
echo "CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${userpass}';" | mysql -u root -p${rootpass}
echo "GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';" | mysql -u root -p${rootpass}
echo "FLUSH PRIVILEGES;" | mysql -u root -p${rootpass}
echo -e "${GREEN}New MySQL database is successfully created{NC}"

#Download and Unzip WordPress
cd /tmp && curl -O https://wordpress.org/latest.tar.gz && tar xzvf latest.tar.gz
#Configure WordPress
touch /tmp/wordpress/.htaccess && chmod 660 /tmp/wordpress/.htaccess
cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
mkdir /tmp/wordpress/wp-content/uploads && mkdir /tmp/wordpress/wp-content/upgrade
sed -i "s/database_name_here/${dbname}/;s/username_here/${dbuser}/;s/password_here/${userpass}/" /tmp/wordpress/wp-config.php
echo "define('FS_METHOD', 'direct');" >> /tmp/wordpress/wp-config.php
#set WP salts
perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' /tmp/wordpress/wp-config.php
#Move WordPress to VHOST directory
rm -r /var/www/html/*
cp -a /tmp/wordpress/. /var/www/html
#Change permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod g+s {} \;
chmod g+w /var/www/html/wp-content
chmod -R g+w /var/www/html/wp-content/themes && chmod -R g+w /var/www/html/wp-content/plugins
#Clean installation
rm -rf /tmp/wordpress && rm -r latest.tar.gz
echo -e "${GREEN}Complete WordPress instalation${NC}"
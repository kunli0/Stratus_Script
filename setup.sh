#!/bin/bash

green=`tput setaf 2`
reset=`tput sgr0`

clear

# Checking for root

if [ "$(id -u)" != "0" ]; then
	echo "Please rerun as root."
	exit 1
fi

# Installing Application Dependencies

declare -A myArray
myArray=([MariaDB]=mariadb-server [NGINX]=nginx [ClamAV]=clamav [ClamAV-Daemon]=clamav-daemon)

for index in ${!myArray[*]}

do
	if [ $(dpkg-query -W -f='${Status}' ${myArray[$index]} 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
	  echo "${green}Installing $index...${reset}"
	  apt-get -qq install ${myArray[$index]}

	  clear

	  if [ $index = "MariaDB" ]; then
		echo "${green}Configuring MariaDB...${reset}"

		MAINDB=stratus
		PASSWDDB='Str@tus1'

		mysql -e "CREATE DATABASE ${MAINDB} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
		mysql -e "CREATE USER ${MAINDB}@localhost IDENTIFIED BY '${PASSWDDB}';"
		mysql -e "GRANT ALL PRIVILEGES ON ${MAINDB}.* TO '${MAINDB}'@'localhost';"
		mysql -e "FLUSH PRIVILEGES;"

		clear
	  fi

	else
	  echo "${green}$index already installed${reset}"
	fi
done

# Adding PPA for PHP 7.1

if ! grep -q "^deb .*ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* &> /dev/null; then

    echo "${green}Adding Ondrej PPA...${reset}"
	sudo add-apt-repository -y ppa:ondrej/php -y

	if ! grep -q "^deb .*ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* &> /dev/null; then
		exit 1
	fi

	clear

	echo "${green}Updating and Upgrading Packages...${reset}"

	apt update && sudo apt upgrade -y

	clear
else
	echo "${green}Ondrej PPA already added.${reset}"
fi


# Installing PHP 7.1 and Extensions

declare -A php
php=([PHP:7.1-FPM]=php7.1-fpm [PHP:7.1-XML]=php7.1-xml [PHP:7.1-MBSTRING]=php7.1-mbstring [PHP:7.1-ZIP]=php7.1-zip [PHP:7.1-MYSQL]=php7.1-mysql [PHP:7.1-LDAP]=php7.1-ldap [PHP:7.1-CURL]=php7.1-curl)

for index in ${!php[*]}

do
	if [ $(dpkg-query -W -f='${Status}' ${php[$index]} 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
	  echo "${green}Installing $index...${reset}"
	  apt-get -qq install ${php[$index]}
	  clear
	else
	  echo "${green}$index already installed${reset}"
	fi
done

# Composer Install

echo "${green}Installing Composer...${reset}"

curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

clear

# Git repository

echo "${green}Cloning Git Repository...${reset}"

git clone https://github.com/kunli0/stratus.git /var/www/stratus

clear

# Folder Permissions

echo "${green}Setting up Folder Permissions...${reset}"

chown -R www-data:www-data /var/www/stratus

find /var/www/stratus -type f -exec chmod 644 {} \;

find /var/www/stratus -type d -exec chmod 755 {} \;

clear

# Package Dependencies

echo "${green}Installing Dependencies...${reset}"

cd /var/www/stratus

sudo -u www-data composer install

clear

# Laravel Setup

echo "${green}Configuring Laravel...${reset}"

cp .env.example .env

chown www-data:www-data /var/www/stratus/.env

chmod 644 /var/www/stratus/.env

php artisan key:generate

sudo -u www-data php artisan migrate --seed

clear

# NGINX Setup

echo "${green}Configuring NGINX Sites...${reset}"

cat > /etc/nginx/sites-available/stratus << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/stratus/public;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri /index.php =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php7.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

ln -s /etc/nginx/sites-available/stratus /etc/nginx/sites-enabled/stratus

rm /etc/nginx/sites-available/default

service nginx restart

clear

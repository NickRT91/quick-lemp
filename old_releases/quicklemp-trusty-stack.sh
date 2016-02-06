#!/bin/bash
echo '[quick-lemp] LEMP Stack Installation'
echo 'Configured for Ubuntu 14.04.'
echo 'Installs Nginx, MariaDB, PHP-FPM, and uWSGI.'
echo
read -p 'Do you want to continue? [y/N] ' -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo 'Exiting...'
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
   echo 'This script must be run with root privileges.' 1>&2
   exit 1
fi

# Update packages and add MariaDB repository
echo -e '\n[Package Updates]'
apt-get install software-properties-common
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
add-apt-repository 'deb http://mirrors.syringanetworks.net/mariadb/repo/10.0/ubuntu trusty main'
add-apt-repository ppa:nginx/stable
apt-get update
apt-get -y upgrade

# Depencies and pip
echo -e '\n[Dependencies]'
apt-get -y install build-essential debconf-utils python-dev libpcre3-dev libssl-dev python-pip

# Nginx
echo -e '\n[Nginx]'
apt-get -y install nginx
service nginx stop
mv /etc/nginx /etc/nginx-previous
curl -L https://github.com/h5bp/server-configs-nginx/archive/1.0.0.tar.gz | tar -xz
# Newer: https://github.com/h5bp/server-configs-nginx/archive/master.zip
mv server-configs-nginx-1.0.0 /etc/nginx
cp /etc/nginx-previous/uwsgi_params /etc/nginx-previous/fastcgi_params /etc/nginx
sed -i.bak -e
sed -i.bak -e "s/www www/www-data www-data/" \
  -e "s/logs\/error.log/\/var\/log\/nginx\/error.log/" \
  -e "s/logs\/access.log/\/var\/log\/nginx\/access.log/" /etc/nginx/nginx.conf
sed -i.bak -e "s/logs\/static.log/\/var\/log\/nginx\/static.log/" /etc/nginx/h5bp/location/expires.conf

echo
read -p 'Do you want to create a self-signed SSL cert and configure HTTPS? [y/N] ' -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
  conf1="  listen [::]:443 ssl default_server;\n  listen 443 ssl default_server;\n"
  conf2="  include h5bp/directive-only/ssl.conf;\n  ssl_certificate /etc/ssl/certs/nginx.crt;\n  ssl_certificate_key /etc/ssl/private/nginx.key;"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx.key -out /etc/ssl/certs/nginx.crt
  chmod 400 /etc/ssl/private/nginx.key
else
  conf1=
  conf2=
  conf3=
fi

echo -e "server {
  listen [::]:80 default_server;
  listen 80 default_server;
$conf1
  server_name _;

$conf2
  root /srv/www/lempsample/public;

  charset utf-8;

  error_page 404 /404.html;

  location = /favicon.ico { log_not_found off; access_log off; }

  location = /robots.txt { allow all; log_not_found off; access_log off; }

  location ^~ /static/ {
    alias /srv/www/lempsample/app/static;
  }

  location ~ \\.php\$ {
    try_files \$uri =404;
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$request_filename;
    fastcgi_index index.php;
    include fastcgi_params;
  }

  location / { try_files \$uri @lempsample; }

  location @lempsample {
    include uwsgi_params;
    uwsgi_pass unix:/tmp/lempsample.sock;
  }
}" > /etc/nginx/sites-available/lempsample

mkdir -p /srv/www/lempsample/app/static
mkdir -p /srv/www/lempsample/app/templates
mkdir -p /srv/www/lempsample/public
ln -s /etc/nginx/sites-available/lempsample /etc/nginx/sites-enabled/lempsample

# PHP
echo -e '\n[PHP-FPM]'
apt-get -y install php5-common php5-mysqlnd php5-curl php5-gd php5-cli php5-fpm php-pear php5-dev php5-imap php5-mcrypt
echo '<?php phpinfo(); ?>' > /srv/www/lempsample/public/checkinfo.php


# uWSGI
echo -e '\n[uWSGI]'
pip install uwsgi
mkdir /etc/uwsgi
mkdir /var/log/uwsgi
echo 'description "uWSGI Emperor"
start on runlevel [2345]
stop on runlevel [06]
exec uwsgi --die-on-term --emperor /etc/uwsgi --logto /var/log/uwsgi/uwsgi.log' > /etc/init/uwsgi-emperor.conf
echo '[uwsgi]
chdir = /srv/www/lempsample
logto = /var/log/uwsgi/lempsample.log
virtualenv = /srv/www/lempsample/venv
socket = /tmp/lempsample.sock
uid = www-data
gid = www-data
master = true
wsgi-file = wsgi.py
callable = app
vacuum = true' > /etc/uwsgi/lempsample.ini
tee -a /srv/www/lempsample/wsgi.py > /dev/null <<EOF
from flask import Flask

app = Flask(__name__)
from flask import render_template

@app.route('/')
def index():
    return "<html><head><link href='https://fonts.googleapis.com/css?family=Noto+Sans' rel='stylesheet' type='text/css'></head><body class='container' style=\"font-family: 'Noto Sans', sans-serif;\"><blockquote><h1>You've got a LEMP stack!!</h1><p>The Python app using uWSGI works! <a href='checkinfo.php'>Try out the PHP page.</a></p><footer><a href='https://github.com/jbradach'>@jbradach</a></footer></blockquote></body></html>"
EOF

# virtualenv
echo -e '\n[virtualenv]'
pip install virtualenv
cd /srv/www/lempsample
virtualenv venv
source venv/bin/activate
pip install flask
deactivate

# Permissions
echo -e '\n[Adjusting Permissions]'
chgrp -R www-data /srv/www/*
chmod -R g+rw /srv/www/*
sh -c 'find /srv/www/* -type d -print0 | sudo xargs -0 chmod g+s'

# MariaDB
echo -e '\n[MariaDB]'
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mariadb-server
echo
start uwsgi-emperor
service nginx restart
service php5-fpm restart
echo
echo '[quick-lemp] LEMP Stack Installation Complete'

exit 0

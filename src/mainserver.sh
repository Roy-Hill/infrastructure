#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

if [ -z "$1" ]; then
    echo "You need to specify arguments for this script."
    echo "bash mainserver.sh secrets # Allow script to run, after you have configured secrets and SSH private key."
    echo "bash mainserver.sh secrets sync # Sync data from backup server."
    exit
fi

# Do everything in general.sh first
/usr/bin/bash general.sh secrets

# Change SSH Port
/usr/bin/sed -i 's/#Port 22/Port 1000/g' /etc/ssh/sshd_config
/usr/bin/systemctl restart sshd

# Install docker
## INFO: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
/usr/bin/sudo /usr/bin/mkdir -p /etc/apt/keyrings
/usr/bin/curl -fsSL https://download.docker.com/linux/ubuntu/gpg | /usr/bin/sudo /usr/bin/gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | /usr/bin/sudo /usr/bin/tee /etc/apt/sources.list.d/docker.list > /dev/null
/usr/bin/sudo /usr/bin/apt-get update
/usr/bin/sudo /usr/bin/apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y

# Install Plex
echo "deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main" | /usr/bin/sudo /usr/bin/tee /etc/apt/sources.list.d/plexmediaserver.list
/usr/bin/sudo /usr/bin/wget -O- https://downloads.plex.tv/plex-keys/PlexSign.key | /usr/bin/gpg --dearmor | /usr/bin/sudo /usr/bin/tee /usr/share/keyrings/plex.gpg
/usr/bin/sudo /usr/bin/apt-get update
/usr/bin/sudo /usr/bin/apt-get install plexmediaserver -y

# Install main server packages
PACKAGES="
apache2
mysql-server
php
php-bcmath
php-bz2
php-curl
php-intl
php-mbstring
php-mysql
php-readline
php-xml
php-zip
php-apcu
php-cli
php-common
php-fpm
php-gd
php-igbinary
php-imagick
php-json
php-pear
php-redis
php-dev
php-gmp
php-opcache
php-soap
libapache2-mod-php
snapd
nodejs
npm
"
/usr/bin/apt install -y "$(tr '\n' ' ' <<< "$PACKAGES")"

# Ensure docker is running
/usr/bin/systemctl enable --now docker

# Copy secrets
/usr/bin/cp ./resources/secrets/*.txt ~

# Add crontabs
(/usr/bin/crontab -l ; echo "*/15 * * * * /root/ddns.sh") | /usr/bin/crontab -
(/usr/bin/crontab -l ; echo "0 0 * * * certbot renew --dns-cloudflare --dns-cloudflare-credentials /root/CF-certbot.txt") | /usr/bin/crontab -
(/usr/bin/crontab -l ; echo "0 1 * * * /root/Scripts/Backup/Backup.sh") | /usr/bin/crontab -
(/usr/bin/crontab -l ; echo "0 2 * * * docker image prune -a -f && docker volume prune -f && docker network prune -f") | /usr/bin/crontab -
(/usr/bin/crontab -l ; echo "0 * * * * curl --silent https://missionpark.net?es=cron&guid=edaiqo-pgoemj-cenpat-cbgkjr-fomgjy > /dev/null 2>&1") | /usr/bin/crontab -

# MySQL setup
## Set MySQL root password
/usr/bin/mysqladmin -u root password "$(cat ~/DB_PW.txt)"
## Remove test database
/usr/bin/mysql -u root -p"$(cat ~/DB_PW.txt)" -e "DROP DATABASE test;"

# Snaps
/usr/bin/snap refresh
/usr/bin/snap install certbot --classic
/usr/bin/snap set certbot trust-plugin-with-root=ok
/usr/bin/snap install certbot-dns-cloudflare
/usr/bin/snap connect certbot:plugin certbot-dns-cloudflare

# Apache
## Enable modules
APACHE_MODULES="
actions
headers
proxy
proxy_ajp
proxy_balancer
proxy_connect
proxy_fcgi
proxy_html
proxy_http
proxy_wstunnel
rewrite
slotmem_shm
socache_shmcb
ssl
xml2enc
http2
"
/usr/sbin/a2enmod "$(tr '\n' ' ' <<< "$APACHE_MODULES")"
/usr/bin/systemctl restart apache2

if [ "$2" = "sync" ]; then
    # Sync data from backup server
    ## WWW Stuff
    backupIP="real.chse.dev"
    DB_PW=$(cat ~/DB_PW.txt)
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/var-www/ /var/www/
    /usr/bin/chown -R www-data:www-data /var/www/
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/etc-apache2/ /etc/apache2/
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/etc-letsencrypt/ /etc/letsencrypt/
    /usr/bin/rsync -az -e 'ssh -p1000 -o ScriptHostKeyChecking=no' root@backupIP:/root/backups/www/WWW-SQL-Dump.sql /tmp/WWW-SQL-Dump.sql
    /usr/bin/mysql -u root -p"$DB_PW" < /tmp/WWW-SQL-Dump.sql
    /usr/bin/rm /tmp/WWW-SQL-Dump.sql
    /usr/bin/systemctl restart apache2
    ## Home Folder
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/hs/root-home/ /root/
    ## Docker Stuff
    /usr/bin/mkdir -p /dockerData
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/hs/docker/ /dockerData/
fi

# Use docker-compose to start all the containers
cd ./resources || exit
/usr/bin/docker compose up -d
cd ../

# npm
/usr/local/bin/npm install -g n
n 16
/usr/local/bin/npm install -g pm2

# github-ci-runner
/usr/sbin/useradd -m -s /bin/bash -G sudo,wheel -p "$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | /usr/bin/head -c"${1:-32}";echo;)" github-ci-runner
if [ "$2" = "sync" ]; then
    /usr/bin/rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@"$backupIP":/root/backups/hs/github-ci-runner/ /home/github-ci-runner/
fi

# KVM/Cockpit
## Install KVM
/usr/bin/apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin
/usr/bin/systemctl enable --now libvirtd
## Install Cockpit
/usr/bin/apt install cockpit cockpit-machines -y
/usr/bin/systemctl enable --now cockpit.socket

echo
echo "Done!"
echo "Please go setup Docker container secrets."
echo "Also, setup Plex by going to: http://MACHINEIP:32400/web"
echo

cd ~ || exit

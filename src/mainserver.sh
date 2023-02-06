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
bash general.sh secrets

# Change SSH Port
sed -i 's/#Port 22/Port 1000/g' /etc/ssh/sshd_config
systemctl restart sshd

# Install docker
## INFO: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y

# Install Plex
echo "deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list
sudo wget -O- https://downloads.plex.tv/plex-keys/PlexSign.key | gpg --dearmor | sudo tee /usr/share/keyrings/plex.gpg
sudo apt-get update
sudo apt-get install plexmediaserver -y

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
apt install -y "$(tr '\n' ' ' <<< "$PACKAGES")"

# Ensure docker is running
systemctl enable --now docker

# Copy secrets
cp ./resources/secrets/*.txt ~

# Add crontabs
(crontab -l ; echo "*/15 * * * * /root/ddns.sh") | crontab -
(crontab -l ; echo "0 0 * * * certbot renew --dns-cloudflare --dns-cloudflare-credentials /root/CF-certbot.txt") | crontab -
(crontab -l ; echo "0 1 * * * /root/Scripts/Backup/Backup.sh") | crontab -
(crontab -l ; echo "0 2 * * * docker image prune -a -f && docker volume prune -f && docker network prune -f") | crontab -
(crontab -l ; echo "0 * * * * curl --silent https://missionpark.net?es=cron&guid=edaiqo-pgoemj-cenpat-cbgkjr-fomgjy > /dev/null 2>&1") | crontab -

# Add www-data crontabs
sudo -u www-data crontab -l | { cat; echo "flock /tmp php --define apc.enable_cli=1 -f /var/www/nextcloud/cron.php"; } | sudo -u www-data crontab -

# MySQL setup
## Set MySQL root password
mysqladmin -u root password "$(cat ~/DB_PW.txt)"
## Remove test database
mysql -u root -p"$(cat ~/DB_PW.txt)" -e "DROP DATABASE test;"

# Snaps
snap refresh
snap install certbot --classic
snap set certbot trust-plugin-with-root=ok
snap install certbot-dns-cloudflare
snap connect certbot:plugin certbot-dns-cloudflare

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
a2enmod "$(tr '\n' ' ' <<< "$APACHE_MODULES")"
systemctl restart apache2

if [ "$2" = "sync" ]; then
    # Sync data from backup server
    ## WWW Stuff
    backupIP="real.chse.dev"
    DB_PW=$(cat ~/DB_PW.txt)
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/var-www/ /var/www/
    chown -R www-data:www-data /var/www/
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/etc-apache2/ /etc/apache2/
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/www/etc-letsencrypt/ /etc/letsencrypt/
    rsync -az -e 'ssh -p1000 -o ScriptHostKeyChecking=no' root@backupIP:/root/backups/www/WWW-SQL-Dump.sql /tmp/WWW-SQL-Dump.sql
    mysql -u root -p"$DB_PW" < /tmp/WWW-SQL-Dump.sql
    rm /tmp/WWW-SQL-Dump.sql
    systemctl restart apache2
    ## Home Folder
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/hs/root-home/ /root/
    ## Docker Stuff
    mkdir -p /dockerData
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/hs/docker/ /dockerData/
fi

# Use docker-compose to start all the containers
cd ./resources || exit
docker compose up -d
cd ../

# npm
npm install -g n
n 16
npm install -g pm2

# github-ci-runner
useradd -m -s /bin/bash -G sudo,wheel -p "$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c"${1:-32}";echo;)" github-ci-runner
if [ "$2" = "sync" ]; then
    rsync -azrdu --delete -e 'ssh -p1000 -o StrictHostKeyChecking=no' root@$backupIP:/root/backups/hs/github-ci-runner/ /home/github-ci-runner/
fi

# KVM/Cockpit
## Install KVM
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin
systemctl enable --now libvirtd
## Install Cockpit
apt install cockpit cockpit-machines -y
systemctl enable --now cockpit.socket

echo
echo "Done!"
echo "Please go setup Docker container secrets."
echo "Also, setup Plex by going to: http://MACHINEIP:32400/web"
echo

cd ~ || exit

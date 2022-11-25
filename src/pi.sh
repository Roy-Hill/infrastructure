#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

# Do everything in general.sh first
bash general.sh

# Change SSH Port
sed -i 's/#Port 22/Port 1010/g' /etc/ssh/sshd_config
systemctl restart sshd

# Make backup locations
mkdir -p ~/backups/{ms,miab}
mkdir -p ~/backups/ms/www/{var-www,etc-apache2,etc-letsencrypt}
mkdir -p ~/backups/miab/
mkdir -p ~/backups/ms/{docker,root-home,github-ci-runner}

cd ~ || exit

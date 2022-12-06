#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

if [ -z "$1" ]; then
    echo "You need to specify arguments for this script."
    echo "bash miab.sh secrets # Allow script to run, after you have configured secrets and SSH private key."
    exit
fi

# Do everything in general.sh first
bash general.sh secrets

# Change SSH Port
sed -i 's/#Port 22/Port 22/g' /etc/ssh/sshd_config
systemctl restart sshd

# Symlink Mail Scripts to ~
ln -s ~/Scripts/Mail/After_MIAB_Upgrade.sh ~/After_MIAB_Upgrade.sh
ln -s ~/Scripts/Mail/Blacklist.sh ~/Blacklist.sh
ln -s ~/Scripts/Mail/Backup.sh ~/Backup.sh

# crontab for backups
(crontab -l ; echo "0 3 * * * /root/Scripts/Mail/Backup.sh") | crontab -

echo "We have gone as far as we can. Please manually install Mail-in-a-box by running:"
echo "curl -s https://mailinabox.email/setup.sh | sudo -E bash"

cd ~ || exit

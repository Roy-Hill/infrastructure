#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

# Do everything in general.sh first
bash general.sh

# Change SSH Port
sed -i 's/#Port 22/Port 22/g' /etc/ssh/sshd_config
systemctl restart sshd

# Symlink Mail Scripts to ~
ln -s ~/Scripts/Mail/After_MIAB_Upgrade.sh ~/After_MIAB_Upgrade.sh
ln -s ~/Scripts/Mail/Blacklist.sh ~/Blacklist.sh

echo "We have gone as far as we can. Please manually install Mail-in-a-box by running:"
echo "curl -s https://mailinabox.email/setup.sh | sudo -E bash"

cd ~ || exit

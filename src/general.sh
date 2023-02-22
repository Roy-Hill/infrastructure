#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

if [ -z "$1" ]; then
    echo "Please do not run this script directly."
    exit
fi

# Update the system
/usr/bin/apt update
/usr/bin/apt upgrade -y

# Install base packages
PACKAGES="
git
curl
wget
unzip
zip
htop
vim
sed
apt-transport-https
ca-certificates
software-properties-common
fail2ban
dos2unix
unattended-upgrades
gnupg
gnupg-agent
lsb-release
rsync
mosh
neofetch
zsh
dialog
"
/usr/bin/apt install -y "$(tr '\n' ' ' <<< "$PACKAGES")"

# Install my SSH key
/usr/bin/mkdir -p ~/.ssh
/usr/bin/chmod 700 ~/.ssh
/usr/bin/cp ./resources/ssh-keys/* ~/.ssh/
/usr/bin/chmod 600 ~/.ssh/*
/usr/bin/cat  ~/.ssh/*.pub >> ~/.ssh/authorized_keys
/usr/bin/chmod 644 ~/.ssh/authorized_keys

# Lockdown SSH
/usr/bin/sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
/usr/bin/sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
/usr/bin/sed -i 's/#PermitRootLogin no/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
/usr/bin/sed -i 's/#UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config
/usr/bin/systemctl restart sshd

# Enable passwordless sudo for user
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set default shell to zsh
/usr/bin/chsh -s "$(which zsh)"

# Disable MOTDs
/usr/bin/touch ~/.hushlogin

# Start fail2ban
/usr/bin/systemctl enable --now fail2ban

# Install oh-my-zsh
/usr/bin/sh -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install zsh plugins
## zsh-autosuggestions
/usr/bin/git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# Install my dotfiles
/usr/bin/git clone https://github.com/chxseh/dotfiles.git ~/.dotfiles
if [ -f ~/.zshrc ]; then /usr/bin/mv ~/.zshrc ~/.zshrc.bak; fi
/usr/bin/ln -s ~/.dotfiles/zshrc ~/.zshrc
if [ -f ~/.vimrc ]; then /usr/bin/mv ~/.vimrc ~/.vimrc.bak; fi
/usr/bin/ln -s ~/.dotfiles/vimrc ~/.vimrc
if [ -f ~/.gitconfig ]; then /usr/bin/mv ~/.gitconfig ~/.gitconfig.bak; fi
/usr/bin/ln -s ~/.dotfiles/gitconfig ~/.gitconfig

# Install my scripts
/usr/bin/git clone https://github.com/chxseh/Scripts.git ~/Scripts

# Setup MOTD
/usr/bin/cp ./resources/motd.sh /etc/motd.sh
/usr/bin/chmod +x /etc/motd.sh

# Setup unattended upgrades
/usr/bin/cp ./resources/unattended-upgrades/* /etc/apt/apt.conf.d/

# sysctl tweaks
/usr/bin/cp ./resources/sysctl.conf /etc/sysctl.conf
/usr/sbin/sysctl -p

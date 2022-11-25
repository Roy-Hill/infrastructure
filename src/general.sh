#!/bin/bash

# Check if we are running as sudo, if not, exit
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Maybe try 'sudo !!'"
    exit
fi

# Update the system
apt update
apt upgrade -y

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
apt install -y "$(tr '\n' ' ' <<< "$PACKAGES")"

# Install my SSH key
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cp ./resources/ssh-keys/* ~/.ssh/
chmod 600 ~/.ssh/*
cat ~/.ssh/*.pub >> ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys

# Lockdown SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin no/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config
systemctl restart sshd

# Enable passwordless sudo for user
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set default shell to zsh
chsh -s "$(which zsh)"

# Disable MOTDs
touch ~/.hushlogin

# Start fail2ban
systemctl enable --now fail2ban

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install zsh plugins
## zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# Install my dotfiles
git clone https://github.com/chxseh/dotfiles.git ~/.dotfiles
if [ -f ~/.zshrc ]; then mv ~/.zshrc ~/.zshrc.bak; fi
ln -s ~/.dotfiles/zshrc ~/.zshrc
if [ -f ~/.vimrc ]; then mv ~/.vimrc ~/.vimrc.bak; fi
ln -s ~/.dotfiles/vimrc ~/.vimrc
if [ -f ~/.gitconfig ]; then mv ~/.gitconfig ~/.gitconfig.bak; fi
ln -s ~/.dotfiles/gitconfig ~/.gitconfig

# Install my scripts
git clone https://github.com/chxseh/Scripts.git ~/Scripts

# Setup MOTD
cp ./resources/motd.sh /etc/motd.sh
chmod +x /etc/motd.sh

# Setup unattended upgrades
cp ./resources/unattended-upgrades/* /etc/apt/apt.conf.d/

# sysctl tweaks
cp ./resources/sysctl.conf /etc/sysctl.conf
sysctl -p

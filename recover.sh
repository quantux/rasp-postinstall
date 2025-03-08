#!/bin/bash

# Checks for root privileges
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Terminal colors
LightColor='\033[1;32m'
NC='\033[0m'

# Get regular user and id
REGULAR_USER_NAME=$(who am i | awk '{print $1}')
REGULAR_UID=$(id -u ${REGULAR_USER_NAME})

# Base project dir
BASE_DIR=$(pwd)

BACKUP_FILE="assets/backups/encrypted"
BACKUP_ENCRYPTION_KEY="assets/backups/encrypted.key"

show_message() {
    clear
    printf "${LightColor}$1${NC}\n\n"
}

user_bash_do() {
    su - mths -c "$1"
}

user_zsh_do() {
    su - ${REGULAR_USER_NAME} -c "/bin/zsh --login -c '$1'"
}

# Pedir a senha para recuperação do gpg e criação/criptografia do arquivo sparse (pegar do bitwarden)
#...

# Check if backup file exists
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Erro: O arquivo de backup não foi encontrado em '$BACKUP_FILE'. Saindo..."
    exit 1
fi

# Check if backup key exists
if [[ ! -f "$BACKUP_ENCRYPTION_KEY" ]]; then
    echo "Erro: O arquivo de backup não foi encontrado em '$BACKUP_FILE'. Saindo..."
    exit 1
fi

# asks for LUKS password confirmation
while true; do
  read -s -p "LUKS Password: " password
  echo
  read -s -p "LUKS Password confirmation: " password2
  echo
  [ "$password" = "$password2" ] && break
  echo "Please try again"
done

# Install apt-get packages
show_message "Instalando pacotes"
apt-get install -y \
  docker.io \
  docker-compose \
  apt-utils \
  iptables-persistent \
  build-essential \
  git \
  curl \
  wget \
  gpg \
  ca-certificates \
  gnupg \
  zsh \
  tmux \
  vim \
  tree \
  speedtest-cli \
  whois \
  nmap \
  traceroute \
  jq \
  f3 \
  qemu-kvm \
  qemu-user-static \
  binfmt-support \
  ffmpeg \
  rename \
  cryptsetup \
  fdisk \
  ecryptfs-utils

# Git config
user_bash_do "git config --global user.name 'Matheus Faria'"
user_bash_do "git config --global user.email 'mths.faria@outlook.com'"
user_bash_do "git config --global credential.helper 'store --file=\$HOME/encrypted/.git-credentials'"

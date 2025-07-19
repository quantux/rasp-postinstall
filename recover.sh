#!/bin/bash

# Verifica se o script está sendo executado com privilégios de root
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Variáveis
REGULAR_USER_NAME="${SUDO_USER:-$LOGNAME}"
HOME=/home/$REGULAR_USER_NAME
CRON_ROOT_PATH=/var/spool/cron/crontabs/root
CRON_USER_PATH=/var/spool/cron/crontabs/$REGULAR_USER_NAME
LUKS_FILE="$HOME/.encrypted"
LUKS_NAME="encrypted_volume"
MOUNT_POINT="$HOME/encrypted"
RCLONE_CONFIG_PATH="$MOUNT_POINT/.config/rclone/"
RCLONE_CONFIG_FILE="$RCLONE_CONFIG_PATH/rclone.conf"

# Função para executar comandos como o usuário regular
user_do() {
    su - ${REGULAR_USER_NAME} -c "/bin/zsh --login -c '$1'"
}

echo -n "Caminho para a chave LUKS: "
read LUKS_KEY_FOLDER

# Rejeita se não for um diretório existente
if [ ! -d "$LUKS_KEY_FOLDER" ]; then
    echo "Erro: o caminho não é um diretório existente."
    exit 1
fi

KEY_FILE="$LUKS_KEY_FOLDER/.enc"

clear

# Instala os pacotes necessários
apt-get update
apt-get install -y \
  restic \
  python3-pip \
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
  ecryptfs-utils \
  gawk \
  kiwix-tools \
  rclone

# Cria a chave privada
head -c 64 /dev/random > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Cria o arquivo sparse
FREE_SPACE=$(( $(df --output=avail / | tail -n1) * 1024 ))
FILE_SIZE=$((FREE_SPACE - 10 * 1024 * 1024 * 1024))
dd if=/dev/zero of="$LUKS_FILE" bs=1 count=0 seek="$FILE_SIZE"

# Formata e monta volume LUKS
cryptsetup luksFormat "$LUKS_FILE" "$KEY_FILE"
echo "/dev/mapper/$LUKS_NAME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
echo "$LUKS_NAME   $LUKS_FILE   $KEY_FILE   luks,noauto,nofail" >> /etc/crypttab
cryptsetup luksOpen "$LUKS_FILE" "$LUKS_NAME" --key-file "$KEY_FILE"
mkfs.ext4 "/dev/mapper/$LUKS_NAME"
mkdir -p "$MOUNT_POINT"
mount "/dev/mapper/$LUKS_NAME" "$MOUNT_POINT"

# Cria pastas
mkdir -p $MOUNT_POINT/Vídeos
mkdir -p $RCLONE_CONFIG_PATH

echo "Cole o conteúdo completo do seu rclone.conf abaixo."
echo "Quando terminar, pressione Ctrl+D para continuar."
echo ">>>"

cat > "$RCLONE_CONFIG_FILE"
export RCLONE_CONFIG="$RCLONE_CONFIG_FILE"

clear

echo -n "RESTIC_REPOSITORY: "
read RESTIC_REPOSITORY
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY"

clear

# Restaura o backup
restic restore latest \
    --target / \
    --tag mths \
    --tag raspberry_pi

# Cria links simbólicos
ln -s "$MOUNT_POINT/.zshrc" "$HOME/.zshrc"
ln -s "$RCLONE_CONFIG_FILE" "$HOME/.config/rclone/rclone.conf"

# Verifica se o .env foi restaurado
DOTENV="$MOUNT_POINT/.env"
if [[ ! -f "$DOTENV" ]]; then
    echo "Erro: O arquivo .env não foi encontrado em $DOTENV."
    exit 1
fi

# Carrega as variáveis do .env
source "$DOTENV"
GIT_NAME="$GIT_NAME"
GIT_EMAIL="$GIT_EMAIL"
GIT_CREDENTIALS_PATH="$GIT_CREDENTIALS_PATH"
DOCKER_COMPOSE_PATH="$DOCKER_COMPOSE_PATH"
RCLONE_DROPBOX_OBSIDIAN_PATH="$RCLONE_DROPBOX_OBSIDIAN_PATH"
SYNCTHING_OBSIDIAN_PATH="$SYNCTHING_OBSIDIAN_PATH"

# Clona repositórios
git clone https://github.com/quantux/convert_to_jellyfin $HOME/workspace/convert_to_jellyfin
git clone https://github.com/quantux/rpi-check-connection $HOME/workspace/rpi-check-connection

# Rede e iptables
mv $HOME/encrypted/.preconfigured.nmconnection /etc/NetworkManager/system-connections/preconfigured.nmconnection
echo "dtoverlay=disable-wifi" >> /boot/firmware/config.txt
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
iptables-save

# Git
user_do "git config --global user.name \"$GIT_NAME\""
user_do "git config --global user.email \"$GIT_EMAIL\""
user_do "git config --global credential.helper \"store --file=$GIT_CREDENTIALS_PATH\""

# NodeJS
user_do "asdf set -u nodejs latest"

# Docker
# Remove pacotes antigos relacionados ao Docker
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    apt-get remove -y "$pkg"
done

# Cria diretório para chave GPG do Docker
install -m 0755 -d /etc/apt/keyrings

# Baixa a chave GPG do Docker
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Adiciona o repositório oficial do Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
> /etc/apt/sources.list.d/docker.list

# Atualiza repositórios e instala pacotes Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Adiciona usuário ao grupo docker
usermod -aG docker "${SUDO_USER:-$USER}"

# rclone
rm -rf "$MOUNT_POINT/Syncthing/Obsidian"
mkdir -p "$MOUNT_POINT/Syncthing/Obsidian"
/usr/bin/rclone sync "$RCLONE_DROPBOX_OBSIDIAN_PATH" "$SYNCTHING_OBSIDIAN_PATH" --progress
docker compose -f "$DOCKER_COMPOSE_PATH" up -d

# Crontabs
echo "@reboot $HOME/workspace/rpi-check-connection/rpi-check-connection.sh" >> $CRON_ROOT_PATH
echo "0 5 * * * { apt-get update && apt-get upgrade -y && apt-get autoremove -y; } > $MOUNT_POINT/logs/apt-auto-update.log 2>&1" >> $CRON_ROOT_PATH

echo "*/30 * * * * /usr/bin/rclone sync "$SYNCTHING_OBSIDIAN_PATH" $RCLONE_DROPBOX_OBSIDIAN_PATH > $MOUNT_POINT/logs/rclone-sync.log 2>&1" >> $CRON_USER_PATH
echo "0 5 * * 0 $HOME/workspace/rasp_postinstall/backup.sh > $MOUNT_POINT/logs/backup.sh.log 2>&1" >> $CRON_USER_PATH
echo "0 5 * * * docker exec pihole pihole enable" >> $CRON_USER_PATH
echo "0 13 * * * docker exec pihole pihole disable" >> $CRON_USER_PATH
echo "0 14 * * * docker exec pihole pihole enable" >> $CRON_USER_PATH
echo "0 20 * * * docker exec pihole pihole disable" >> $CRON_USER_PATH

chown $REGULAR_USER_NAME:crontab $CRON_USER_PATH
chown root:crontab $CRON_ROOT_PATH
chmod 600 $CRON_ROOT_PATH $CRON_USER_PATH

# Permissões finais
chown -R $REGULAR_USER_NAME:$REGULAR_USER_NAME $MOUNT_POINT
chown $REGULAR_USER_NAME:$REGULAR_USER_NAME "$HOME/.zshrc"

# ZSH como padrão
chsh -s $(which zsh) $REGULAR_USER_NAME

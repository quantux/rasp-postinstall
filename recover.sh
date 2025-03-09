#!/bin/bash

# Verifica se o script está sendo executado com privilégios de root
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Vars
REGULAR_USER_NAME="${SUDO_USER:-$LOGNAME}"
HOME=/home/$REGULAR_USER_NAME
CRON_ROOT_PATH=/var/spool/cron/crontabs/root
CRON_USER_PATH=/var/spool/cron/crontabs/$REGULAR_USER_NAME
ENCRYPTED_FILE="encrypted.tar.gz.gpg"
EXTRACTION_FOLDER=/tmp/extracted
DOTENV=$EXTRACTION_FOLDER/.env

# Verifica se o arquivo de backup existe
if [[ ! -f "$ENCRYPTED_FILE" ]]; then
    echo "Erro: O arquivo de backup não foi encontrado em $ENCRYPTED_FILE."
    exit 1
fi

# Recupera o arquivo de backup
mkdir -p $EXTRACTION_FOLDER && gpg --batch --yes --decrypt "$ENCRYPTED_FILE" | tar -xzvf - -C "$EXTRACTION_FOLDER"

# Verifica se o GPG retornou um erro (código de saída diferente de 0)
if [ $? -ne 0 ]; then
  echo "Erro: a senha pode estar errada ou ocorreu um problema durante a descriptografia."
  exit 1
fi

# remove encrypted file
rm -f $ENCRYPTED_FILE

# Verifica se o arquivo .env existe
if [[ ! -f "$DOTENV" ]]; then
    echo "Erro: O arquivo .env não foi encontrado."
    exit 1
fi

# Carrega o arquivo .env
source $DOTENV
ENCRYPTION_PASSWORD="$ENCRYPTION_PASSWORD"
KEY_FILE="$KEY_FILE"
LUKS_FILE="$LUKS_FILE"
MOUNT_POINT="$MOUNT_POINT"
LUKS_NAME="$LUKS_NAME"
DOCKER_COMPOSE_PATH="$DOCKER_COMPOSE_PATH"
GIT_NAME="$GIT_NAME"
GIT_EMAIL="$GIT_EMAIL"
GIT_CREDENTIALS_PATH="$GIT_CREDENTIALS_PATH"
DROPBOX_OBSIDIAN_PATH="$DROPBOX_OBSIDIAN_PATH"

user_do() {
    su - ${REGULAR_USER_NAME} -c "/bin/zsh --login -c '$1'"
}

# Cria uma chave privada
head -c 64 /dev/random > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Cria o arquivo sparse
FREE_SPACE=$(( $(df --output=avail / | tail -n1) * 1024 ))  # Converte para bytes
FILE_SIZE=$((FREE_SPACE - 10 * 1024 * 1024 * 1024)) # Aloca todo o espaço, mas deixa 10GB livres
dd if=/dev/zero of="$LUKS_FILE" bs=1 count=0 seek="$FILE_SIZE"

# Formatação LUKS
cryptsetup luksFormat "$LUKS_FILE" "$KEY_FILE"

# Adiciona uma chave para montagem automática
cryptsetup luksAddKey $LUKS_FILE $KEY_FILE

# Adiciona as entradas no /etc/fstab e /etc/crypttab para montagem automática
echo "/dev/mapper/$LUKS_NAME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
echo "encrypted_volume   $HOME/.encrypted   /root/.encrypted.key   luks,noauto,nofail" >> /etc/crypttab > /dev/null

# Abre o volume LUKS
sudo cryptsetup luksOpen $LUKS_FILE $LUKS_NAME --key-file $KEY_FILE

# Cria um sistema de arquivos ext4 no volume LUKS
mkfs.ext4 "/dev/mapper/$LUKS_NAME"

# Cria o diretório de montagem
mkdir -p "$MOUNT_POINT"

# Monta o volume
mount "/dev/mapper/$LUKS_NAME" "$MOUNT_POINT"

echo "Arquivo criptografado e montado em $MOUNT_POINT"

# Move all unpacked files to $MOUNT_POINT
mv $EXTRACTION_FOLDER/* $MOUNT_POINT

# Cria um link simbólico para o .zshrc
ln -s $HOME/encrypted/.zshrc $HOME/.zshrc

# Instala pacotes com apt-get
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
  ecryptfs-utils \
  gawk

# Cron root
echo "@reboot /home/pi/encrypted/workspace/rpi-check-connection/rpi-check-connection.sh" >> /var/spool/cron/crontabs/root
echo "0 5 * * * { apt-get update && apt-get upgrade -y && apt-get autoremove -y; } > /var/log/apt-auto-update.log 2>&1" >> /var/spool/cron/crontabs/root

# Cron user
echo "*/30 * * * * docker-compose -f $DOCKER_COMPOSE_PATH run --rm rclone sync /Backups/Obsidian $DROPBOX_OBSIDIAN_PATH > /var/log/rclone-sync.log 2>&1" >> $CRON_USER_PATH
echo "0 5 * * * docker exec pihole pihole enable" >> $CRON_USER_PATH
echo "0 13 * * * docker exec pihole pihole disable" >> $CRON_USER_PATH
echo "0 14 * * * docker exec pihole pihole enable" >> $CRON_USER_PATH
echo "0 20 * * * docker exec pihole pihole disable" >> $CRON_USER_PATH

# Configurações do Git
user_do "git config --global user.name \"$GIT_NAME\""
user_do "git config --global user.email \"$GIT_EMAIL\""
user_do "git config --global credential.helper \"store --file=$GIT_CREDENTIALS\""

docker-compose -f $DOCKER_COMPOSE_PATH up -d

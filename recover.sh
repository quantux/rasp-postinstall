#!/bin/bash

# Verifica se o script está sendo executado com privilégios de root
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Vars
REGULAR_USER_NAME="${SUDO_USER:-$LOGNAME}"
HOME=/home/$REGULAR_USER_NAME
DOTENV=$HOME/encrypted/.env
ENCRYPTED_FILE=$HOME/.encrypted.tar.gz.gpg
SPARSE_FILE="$HOME/.encrypted"
MOUNT_POINT="$HOME/encrypted"
LUKS_NAME="encrypted_volume"
KEY_FILE="/root/.enc"

user_do() {
    su - ${REGULAR_USER_NAME} -c "/bin/zsh --login -c '$1'"
}

# Verifica se o arquivo .env existe
if [[ ! -f "$DOTENV" ]]; then
    echo "Erro: O arquivo .env não foi encontrado."
    exit 1
fi

# Carrega o arquivo .env
source $DOTENV
ENCRYPTION_PASSWORD="$ENCRYPTION_PASSWORD"

# Verifica se o arquivo de backup existe
if [[ ! -f "$ENCRYPTED_FILE" ]]; then
    echo "Erro: O arquivo de backup não foi encontrado em $ENCRYPTED_FILE."
    exit 1
fi

# Solicita a senha do GPG
while true; do
  read -s -p "GPG Password: " password
  echo
  read -s -p "Password confirmation: " password2
  echo
  [ "$password" = "$password2" ] && break
  echo "Tente novamente"
done

# Cria uma chave privada
head -c 64 /dev/random > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Cria o arquivo sparse
FREE_SPACE=$(( $(df --output=avail / | tail -n1) * 1024 ))  # Converte para bytes
FILE_SIZE=$((FREE_SPACE - 10 * 1024 * 1024 * 1024)) # Aloca todo o espaço, mas deixa 10GB livres
dd if=/dev/zero of="$SPARSE_FILE" bs=1 count=0 seek="$FILE_SIZE"

# Formatação LUKS
cryptsetup luksFormat "$SPARSE_FILE" "$KEY_FILE"

# Adiciona uma chave para montagem automática
cryptsetup luksAddKey $SPARSE_FILE $KEY_FILE

# Adiciona a entrada no /etc/fstab para montagem automática
echo "/dev/mapper/$LUKS_NAME $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab > /dev/null

# Abre o volume LUKS
sudo cryptsetup luksOpen $SPARSE_FILE $LUKS_NAME --key-file $KEY_FILE

# Cria um sistema de arquivos ext4 no volume LUKS
mkfs.ext4 "/dev/mapper/$LUKS_NAME"

# Cria o diretório de montagem
mkdir -p "$MOUNT_POINT"

# Monta o volume
mount "/dev/mapper/$LUKS_NAME" "$MOUNT_POINT"

# Limpa as variáveis de senha da memória
unset password
unset password2

echo "Arquivo criptografado e montado em $MOUNT_POINT"

# Recupera o arquivo de backup
gpg --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSWORD" "$ENCRYPTED_FILE" | tar -xzvf - -C "$MOUNT_POINT"

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

# Configurações do Git
user_do "git config --global user.name 'Matheus Faria'"
user_do "git config --global user.email 'mths.faria@outlook.com'"
user_do "git config --global credential.helper 'store --file=\$HOME/encrypted/.git-credentials'"

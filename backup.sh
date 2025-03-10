#!/bin/bash

# Checks for root privileges
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Get regular user and id
REGULAR_USER_NAME="${SUDO_USER:-$LOGNAME}"
HOME=/home/$REGULAR_USER_NAME
DOTENV=$HOME/encrypted/.env
BACKUP_FOLDER=/tmp/.backups
ENCRYPTED_FILE="$BACKUP_FOLDER/encrypted-$(date +%d-%m-%Y).tar.gz.gpg"
FILES_TO_KEEP=10

# Check if .env file exists
if [[ ! -f "$DOTENV" ]]; then
    echo "Erro: O arquivo .env não foi encontrado."
    exit 1
fi

# Load .env
source $DOTENV
ENCRYPTION_PASSWORD="$ENCRYPTION_PASSWORD"
GDRIVE_PATH="$GDRIVE_PATH"
DOCKER_COMPOSE_PATH="$DOCKER_COMPOSE_PATH"

# Pause containers
docker-compose -f $DOCKER_COMPOSE_PATH pause

# Create backup folder and guarantee folder is clear
mkdir -p $BACKUP_FOLDER && rm -rf $BACKUP_FOLDER/*

# Backup encrypted folder
tar --exclude-from="./ignore-files" -czf - -C "$HOME" encrypted | gpg --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_PASSWORD" --batch -o "$ENCRYPTED_FILE"

# Unpause containers
docker-compose -f $DOCKER_COMPOSE_PATH unpause

# Clear password from memory
unset ENCRYPTION_PASSWORD

# Backup to Cloud Storage
docker exec rclone rclone move --progress $ENCRYPTED_FILE "$GDRIVE_PATH"
echo "Backup concluído!"

# Excluindo arquivos antigos...
docker exec rclone rclone delete --min-age $((FILES_TO_KEEP * 7))d "$GDRIVE_PATH"

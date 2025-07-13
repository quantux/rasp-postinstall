#!/bin/bash

# Checks for root privileges
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# Vars
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGULAR_USER_NAME="${SUDO_USER:-$LOGNAME}"
HOME=/home/$REGULAR_USER_NAME
DOTENV="$HOME/encrypted/.env"
IGNORE_FILE="$SCRIPT_DIR/ignore-files"
FILES_TO_KEEP=5

# Check if .env file exists
if [[ ! -f "$DOTENV" ]]; then
    echo "Erro: O arquivo .env não foi encontrado."
    exit 1
fi

# Load .env
source "$DOTENV"
export RESTIC_PASSWORD
export RESTIC_REPOSITORY
DOCKER_COMPOSE_PATH="$DOCKER_COMPOSE_PATH"

# Pause containers
docker-compose -f "$DOCKER_COMPOSE_PATH" pause

# Backup wifi networks
cat /etc/NetworkManager/system-connections/preconfigured.nmconnection > "$HOME/encrypted/.preconfigured.nmconnection"

# Executa backup com Restic
restic backup "$HOME/encrypted" \
    --exclude-file="$IGNORE_FILE" \
    --tag mths \
    --tag raspberry_pi

# Unpause containers
docker-compose -f "$DOCKER_COMPOSE_PATH" unpause

# Política de retenção
restic forget \
    --tag mths \
    --tag raspberry_pi \
    --keep-last \
    "$FILES_TO_KEEP" \
    --prune

# Limpa variáveis sensíveis
unset RESTIC_PASSWORD
unset RESTIC_REPOSITORY

echo "Backup com Restic concluído com sucesso!"

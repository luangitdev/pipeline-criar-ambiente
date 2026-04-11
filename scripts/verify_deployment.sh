#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

DEPLOY_SERVER_NAME=""
DEPLOY_SERVER_IP=""
TOMCAT_VOLUME=""
APP_NAME=""
SSH_KEY_FILE=""
SUDO_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deploy-server-name)
            DEPLOY_SERVER_NAME="$2"
            shift 2
            ;;
        --deploy-server-ip)
            DEPLOY_SERVER_IP="$2"
            shift 2
            ;;
        --tomcat-volume)
            TOMCAT_VOLUME="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --ssh-key-file)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        --sudo-password)
            SUDO_PASSWORD="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$DEPLOY_SERVER_IP" || -z "$TOMCAT_VOLUME" || -z "$APP_NAME" || -z "$SUDO_PASSWORD" ]]; then
    log_error "Parâmetros obrigatórios faltando para verificação do deploy."
    exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=no)
if [[ -n "$SSH_KEY_FILE" ]]; then
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        log_error "Arquivo de chave SSH não encontrado: $SSH_KEY_FILE"
        exit 1
    fi
    SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

TARGET_BASE="/var/lib/docker/volumes/${TOMCAT_VOLUME}/_data"
TARGET_APP_DIR="${TARGET_BASE}/${APP_NAME}"

log "🔍 Verificando deploy remoto: ${DEPLOY_SERVER_NAME} (${DEPLOY_SERVER_IP})"
log "📂 Caminho esperado: ${TARGET_APP_DIR}"

ssh "${SSH_OPTS[@]}" "infra@${DEPLOY_SERVER_IP}" "bash -s" -- "$SUDO_PASSWORD" "$TARGET_BASE" "$TARGET_APP_DIR" << 'EOS'
set -euo pipefail

SUDO_PASSWORD="$1"
TARGET_BASE="$2"
TARGET_APP_DIR="$3"

run_sudo() {
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
}

if ! run_sudo test -d "$TARGET_BASE"; then
    echo "❌ Volume tomcat não encontrado: $TARGET_BASE"
    exit 1
fi

if ! run_sudo test -d "$TARGET_APP_DIR"; then
    echo "❌ Diretório da aplicação não encontrado: $TARGET_APP_DIR"
    exit 1
fi

FILE_COUNT=$(run_sudo find "$TARGET_APP_DIR" -type f | wc -l | tr -d ' ')
DIR_SIZE=$(run_sudo du -sh "$TARGET_APP_DIR" | awk '{print $1}')

echo "✅ Diretório da aplicação encontrado"
echo "📊 Total de arquivos: $FILE_COUNT"
echo "📦 Tamanho total: $DIR_SIZE"

if [[ "$FILE_COUNT" -lt 10 ]]; then
    echo "⚠️ Poucos arquivos no diretório da aplicação; valide extração/publicação"
fi

if run_sudo find "$TARGET_APP_DIR" -type f -name "login.properties" | grep -q .; then
    echo "✅ login.properties localizado"
else
    echo "⚠️ login.properties não encontrado"
fi

if run_sudo find "$TARGET_APP_DIR" -type f -name "application.properties" | grep -q .; then
    echo "✅ application.properties localizado"
else
    echo "⚠️ application.properties não encontrado"
fi
EOS

log_success "Verificação de deploy concluída com sucesso"

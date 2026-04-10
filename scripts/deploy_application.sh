#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

upsert_property() {
    local file="$1"
    local key="$2"
    local value="$3"

    local escaped
    escaped="$(escape_sed_replacement "$value")"

    if grep -qE "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

WAR_FILE=""
NOME_BANCO=""
DB_HOST=""
TIPO_AMBIENTE=""
DEPLOY_SERVER_NAME=""
DEPLOY_SERVER_IP=""
TOMCAT_VOLUME=""
APP_NAME=""
WORKSPACE=""
SUDO_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --war-file)
            WAR_FILE="$2"
            shift 2
            ;;
        --nome-banco)
            NOME_BANCO="$2"
            shift 2
            ;;
        --db-host)
            DB_HOST="$2"
            shift 2
            ;;
        --tipo-ambiente)
            TIPO_AMBIENTE="$2"
            shift 2
            ;;
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
        --workspace)
            WORKSPACE="$2"
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

if [[ -z "$WAR_FILE" || -z "$NOME_BANCO" || -z "$DB_HOST" || -z "$DEPLOY_SERVER_NAME" || -z "$DEPLOY_SERVER_IP" || -z "$TOMCAT_VOLUME" || -z "$APP_NAME" || -z "$WORKSPACE" || -z "$SUDO_PASSWORD" ]]; then
    log_error "Parâmetros obrigatórios faltando para o deploy."
    exit 1
fi

if [[ ! -f "$WAR_FILE" ]]; then
    log_error "Arquivo WAR não encontrado: $WAR_FILE"
    exit 1
fi

if [[ "$APP_NAME" == */* ]]; then
    log_error "APP_NAME inválido: não use '/'."
    exit 1
fi

LANGUAGE_ENDPOINT=""
case "$DEPLOY_SERVER_NAME" in
    IMP-01) LANGUAGE_ENDPOINT="10.0.16.19:8099" ;;
    PROD-01) LANGUAGE_ENDPOINT="10.0.16.13:8099" ;;
    PROD-02) LANGUAGE_ENDPOINT="10.0.16.14:8099" ;;
    PROD-03) LANGUAGE_ENDPOINT="10.0.16.22:8099" ;;
    PROD-04) LANGUAGE_ENDPOINT="10.0.16.23:6030" ;;
    PROD-06) LANGUAGE_ENDPOINT="10.0.16.27:8099" ;;
    PROD-10) LANGUAGE_ENDPOINT="10.0.31.192:8099" ;;
    PROD-11) LANGUAGE_ENDPOINT="10.0.16.49:8099" ;;
    PROD-05|PROD-07|PROD-08|PROD-09) LANGUAGE_ENDPOINT="" ;;
    *)
        log_warning "Servidor ${DEPLOY_SERVER_NAME} não mapeado para ptf-idioma.language-url; valor atual será mantido."
        LANGUAGE_ENDPOINT=""
        ;;
esac

log "🚀 INICIANDO DEPLOY DA APLICAÇÃO"
log "📋 Configuração:"
log "   - Ambiente: $TIPO_AMBIENTE"
log "   - Banco: $NOME_BANCO"
log "   - DB Host: $DB_HOST:5432"
log "   - Deploy Target: $DEPLOY_SERVER_NAME ($DEPLOY_SERVER_IP)"
log "   - Tomcat Volume: $TOMCAT_VOLUME"
log "   - App Name: $APP_NAME"

STAGING_ROOT="$WORKSPACE/temp/deploy_payload"
APP_STAGING_DIR="$STAGING_ROOT/$APP_NAME"
TAR_FILE="$WORKSPACE/temp/${APP_NAME}.tar.gz"

rm -rf "$APP_STAGING_DIR"
mkdir -p "$APP_STAGING_DIR"

log "📦 Extraindo WAR para pasta de publicação (${APP_NAME}/)"
(
    cd "$APP_STAGING_DIR"
    jar -xf "$WAR_FILE"
)

mapfile -t login_files < <(find "$APP_STAGING_DIR" -type f -name "login.properties")
if [[ "${#login_files[@]}" -eq 0 ]]; then
    log_warning "Nenhum login.properties encontrado no conteúdo extraído."
else
    for file in "${login_files[@]}"; do
        log "⚙️ Atualizando login.properties: $file"
        upsert_property "$file" "database.serverHost" "${DB_HOST}:5432"
        upsert_property "$file" "database.databaseName" "$NOME_BANCO"
        upsert_property "$file" "database.user" "pathfinddb"
        upsert_property "$file" "database.password" "Find**(path)\$DB"
        upsert_property "$file" "database.jdbcurl" "jdbc:postgresql://${DB_HOST}:5432/${NOME_BANCO}"
    done
fi

mapfile -t app_prop_files < <(find "$APP_STAGING_DIR" -type f -name "application.properties")
if [[ "${#app_prop_files[@]}" -eq 0 ]]; then
    log_warning "Nenhum application.properties encontrado no conteúdo extraído."
else
    if [[ -n "$LANGUAGE_ENDPOINT" ]]; then
        language_url="http://${LANGUAGE_ENDPOINT}/api/v1"
        for file in "${app_prop_files[@]}"; do
            log "⚙️ Atualizando ptf-idioma.language-url em: $file"
            upsert_property "$file" "ptf-idioma.language-url" "$language_url"
        done
    else
        log "ℹ️ Mapeamento de idioma desconsiderado para $DEPLOY_SERVER_NAME; valor atual será mantido."
    fi
fi

rm -f "$TAR_FILE"
tar -C "$STAGING_ROOT" -czf "$TAR_FILE" "$APP_NAME"

REMOTE_TMP_PREFIX="/tmp/${APP_NAME}_deploy_${RANDOM}_$$"
REMOTE_TAR_FILE="${REMOTE_TMP_PREFIX}.tar.gz"

log "📤 Copiando pacote para o servidor alvo"
scp -o StrictHostKeyChecking=no "$TAR_FILE" "infra@${DEPLOY_SERVER_IP}:${REMOTE_TAR_FILE}"

log "🚚 Publicando aplicação em /var/lib/docker/volumes/${TOMCAT_VOLUME}/_data/${APP_NAME}"
ssh -o StrictHostKeyChecking=no "infra@${DEPLOY_SERVER_IP}" "bash -s" -- "$SUDO_PASSWORD" "$TOMCAT_VOLUME" "$APP_NAME" "$REMOTE_TMP_PREFIX" << 'EOS'
set -euo pipefail

SUDO_PASSWORD="$1"
TOMCAT_VOLUME="$2"
APP_NAME="$3"
REMOTE_TMP_PREFIX="$4"
REMOTE_TAR_FILE="${REMOTE_TMP_PREFIX}.tar.gz"
TARGET_BASE="/var/lib/docker/volumes/${TOMCAT_VOLUME}/_data"
TARGET_APP_DIR="${TARGET_BASE}/${APP_NAME}"
BACKUP_DIR="${TARGET_BASE}/${APP_NAME}_backup_$(date +%Y%m%d_%H%M%S)"

run_sudo() {
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
}

if ! run_sudo test -d "$TARGET_BASE"; then
    echo "❌ Volume do tomcat não encontrado: $TARGET_BASE"
    exit 1
fi

mkdir -p "$REMOTE_TMP_PREFIX"
tar -xzf "$REMOTE_TAR_FILE" -C "$REMOTE_TMP_PREFIX"

if [[ ! -d "${REMOTE_TMP_PREFIX}/${APP_NAME}" ]]; then
    echo "❌ Conteúdo extraído inválido: pasta ${APP_NAME} não encontrada"
    exit 1
fi

if run_sudo test -d "$TARGET_APP_DIR"; then
    run_sudo cp -a "$TARGET_APP_DIR" "$BACKUP_DIR"
    echo "📦 Backup da aplicação anterior: $BACKUP_DIR"
fi

run_sudo rm -rf "$TARGET_APP_DIR"
run_sudo mv "${REMOTE_TMP_PREFIX}/${APP_NAME}" "$TARGET_APP_DIR"
run_sudo chown -R infra:infra "$TARGET_APP_DIR" || true
run_sudo chmod -R u+rwX,go+rX "$TARGET_APP_DIR" || true

rm -rf "$REMOTE_TMP_PREFIX"
rm -f "$REMOTE_TAR_FILE"
EOS

log_success "Deploy concluído com sucesso"
log "📋 Resumo:"
log "   - Target: ${DEPLOY_SERVER_NAME} (${DEPLOY_SERVER_IP})"
log "   - Tomcat: /var/lib/docker/volumes/${TOMCAT_VOLUME}/_data"
log "   - Aplicação: ${APP_NAME}"

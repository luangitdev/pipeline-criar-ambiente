#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log_utils.sh"

# Parameters
REDIRECT_SERVER_IP=""
REDIRECT_MAPPINGS=""
APP_NAME=""
WORKSPACE=""
SSH_KEY_FILE=""
SSH_USER="infra"
SUDO_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --redirect-server-ip)
            REDIRECT_SERVER_IP="$2"
            shift 2
            ;;
        --redirect-mappings)
            REDIRECT_MAPPINGS="$2"
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
        --ssh-key-file)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
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

# Validate required parameters
if [[ -z "$REDIRECT_SERVER_IP" || -z "$REDIRECT_MAPPINGS" || -z "$APP_NAME" || -z "$WORKSPACE" || -z "$SUDO_PASSWORD" ]]; then
    log_error "Parâmetros obrigatórios faltando para configuração de redirecionamento."
    exit 1
fi

# Validate APP_NAME
if [[ "$APP_NAME" == */* ]]; then
    log_error "APP_NAME inválido: não use '/'."
    exit 1
fi

# SSH options
SSH_OPTS=(-o StrictHostKeyChecking=no)
if [[ -n "$SSH_KEY_FILE" ]]; then
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        log_error "Arquivo de chave SSH não encontrado: $SSH_KEY_FILE"
        exit 1
    fi
    SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

log "🔧 Configuração de redirecionamento Apache2 para '$APP_NAME' → $REDIRECT_SERVER_IP"

# Parse mappings
IFS=$'\n' read -r -d '' -a MAPPINGS_ARRAY <<< "$REDIRECT_MAPPINGS" || true
if [[ ${#MAPPINGS_ARRAY[@]} -eq 0 ]]; then
    # Try comma separation if newline didn't work
    IFS=',' read -r -a MAPPINGS_ARRAY <<< "$REDIRECT_MAPPINGS"
fi

# Filter out empty mappings
MAPPINGS_ARRAY=($(printf '%s\n' "${MAPPINGS_ARRAY[@]}" | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'))

if [[ ${#MAPPINGS_ARRAY[@]} -eq 0 ]]; then
    log_error "Nenhum mapeamento válido encontrado em REDIRECT_MAPPINGS"
    exit 1
fi

log "📋 Processando ${#MAPPINGS_ARRAY[@]} mapeamentos:"

declare -a CONFIG_LINES
for mapping in "${MAPPINGS_ARRAY[@]}"; do
    # Parse mapping: nome_servidor:tomcat:alias_redirecionamento
    IFS=':' read -r nome_servidor tomcat alias_redirecionamento <<< "$mapping"

    # Trim whitespace
    nome_servidor=$(echo "$nome_servidor" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    tomcat=$(echo "$tomcat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    alias_redirecionamento=$(echo "$alias_redirecionamento" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "$nome_servidor" || -z "$tomcat" || -z "$alias_redirecionamento" ]]; then
        log_warn "Mapeamento inválido ignorado: '$mapping'. Formato esperado: nome_servidor:tomcat:alias_redirecionamento"
        continue
    fi

    config_line="/${APP_NAME}*=${alias_redirecionamento}"
    CONFIG_LINES+=("$config_line")

    log "  → $nome_servidor:$tomcat → $config_line"
done

# Execute configuration on remote server
REMOTE_TMP_PREFIX="/tmp/${APP_NAME}_redirect_${RANDOM}_$$"
CONFIG_FILE="${REMOTE_TMP_PREFIX}/uriworkermap_updates.txt"

log "📤 Aplicando configuração no servidor Apache2"

# Create remote temp directory and send configuration lines
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REDIRECT_SERVER_IP}" "mkdir -p ${REMOTE_TMP_PREFIX}"
printf '%s\n' "${CONFIG_LINES[@]}" | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REDIRECT_SERVER_IP}" "cat > $CONFIG_FILE"

# Execute the remote configuration
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REDIRECT_SERVER_IP}" "bash -s" -- "$SUDO_PASSWORD" "$APP_NAME" "$REMOTE_TMP_PREFIX" < <(cat << 'EOF'
set -euo pipefail

SUDO_PASSWORD="$1"
APP_NAME="$2"
REMOTE_TMP_PREFIX="$3"
CONFIG_FILE="${REMOTE_TMP_PREFIX}/uriworkermap_updates.txt"
URIWORKERMAP_FILE="/etc/apache2/uriworkermap.properties"
BACKUP_DIR="/var/backups/apache2"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/uriworkermap.properties.${TIMESTAMP}"

run_sudo() {
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@" 2>/dev/null
}

echo "[REMOTE] 🔧 Iniciando configuração de redirecionamento para $APP_NAME"

# Create backup directory if it doesn't exist
run_sudo mkdir -p "$BACKUP_DIR"

# Backup the original file
if run_sudo test -f "$URIWORKERMAP_FILE"; then
    echo "[REMOTE] 📦 Fazendo backup do arquivo original: $BACKUP_FILE"
    run_sudo cp "$URIWORKERMAP_FILE" "$BACKUP_FILE"

    # Keep only the last 2 backups
    run_sudo ls -t "${BACKUP_DIR}/uriworkermap.properties."* 2>/dev/null | tail -n +3 | xargs -r run_sudo rm -f || true
else
    echo "[REMOTE] 📄 Arquivo uriworkermap.properties não existe, será criado"
    run_sudo touch "$URIWORKERMAP_FILE"
fi

# Read existing content
EXISTING_CONTENT=""
if run_sudo test -f "$URIWORKERMAP_FILE"; then
    EXISTING_CONTENT=$(run_sudo cat "$URIWORKERMAP_FILE")
fi

# Process configuration lines
UPDATED_CONTENT="$EXISTING_CONTENT"
CHANGED=false

while IFS= read -r config_line; do
    if [[ -z "$config_line" ]]; then
        continue
    fi

    # Extract key (everything before =)
    key=$(echo "$config_line" | cut -d'=' -f1)

    if echo "$EXISTING_CONTENT" | grep -q "^${key}="; then
        # Update existing line
        echo "[REMOTE] 📝 Atualizando linha existente: $config_line"
        UPDATED_CONTENT=$(echo "$UPDATED_CONTENT" | sed "s|^${key}=.*|${config_line}|")
        CHANGED=true
    else
        # Add new line
        echo "[REMOTE] ➕ Adicionando nova linha: $config_line"
        UPDATED_CONTENT=$(printf '%s\n%s' "$UPDATED_CONTENT" "$config_line")
        CHANGED=true
    fi
done < "$CONFIG_FILE"

# Only write if content changed
if [[ "$CHANGED" == "true" ]]; then
    # Write updated content to file
    echo "[REMOTE] 💾 Gravando alterações no arquivo uriworkermap.properties"
    printf '%s\n' "$UPDATED_CONTENT" | run_sudo tee "$URIWORKERMAP_FILE" > /dev/null

    # Reload Apache2
    echo "[REMOTE] 🔄 Recarregando Apache2"
    if run_sudo systemctl reload apache2 2>/dev/null; then
        echo "[REMOTE] ✅ Apache2 recarregado com sucesso (systemctl)"
    elif run_sudo service apache2 reload 2>/dev/null; then
        echo "[REMOTE] ✅ Apache2 recarregado com sucesso (service)"
    else
        echo "[REMOTE] ⚠️ Falha ao recarregar Apache2. Verifique manualmente."
    fi

    # Verify service status
    if run_sudo systemctl is-active --quiet apache2 2>/dev/null; then
        echo "[REMOTE] ✅ Apache2 está ativo"
    elif run_sudo service apache2 status 2>/dev/null | grep -q "active"; then
        echo "[REMOTE] ✅ Apache2 está ativo"
    else
        echo "[REMOTE] ⚠️ Status do Apache2 não pôde ser verificado"
    fi
else
    echo "[REMOTE] ℹ️ Nenhuma alteração necessária no arquivo uriworkermap.properties"
fi

# Cleanup
rm -rf "$REMOTE_TMP_PREFIX"

echo "[REMOTE] ✅ Configuração de redirecionamento concluída"
EOF

log_success "Configuração de redirecionamento Apache2 concluída para '$APP_NAME' em $REDIRECT_SERVER_IP"
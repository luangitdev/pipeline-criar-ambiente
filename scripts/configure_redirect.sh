#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log_utils.sh"

REDIRECT_SERVER_IP=""
REDIRECT_MAPPINGS=""
APP_NAME=""
SSH_KEY_FILE=""
SSH_USER="infra"
SUDO_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --redirect-server-ip)   REDIRECT_SERVER_IP="$2";  shift 2 ;;
        --redirect-mappings)    REDIRECT_MAPPINGS="$2";   shift 2 ;;
        --app-name)             APP_NAME="$2";            shift 2 ;;
        --workspace)            shift 2 ;;  # reservado, não utilizado
        --ssh-key-file)         SSH_KEY_FILE="$2";        shift 2 ;;
        --ssh-user)             SSH_USER="$2";            shift 2 ;;
        --sudo-password)        SUDO_PASSWORD="$2";       shift 2 ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$REDIRECT_SERVER_IP" || -z "$REDIRECT_MAPPINGS" || -z "$APP_NAME" || -z "$SUDO_PASSWORD" ]]; then
    log_error "Parâmetros obrigatórios faltando: --redirect-server-ip, --redirect-mappings, --app-name, --sudo-password"
    exit 1
fi

if [[ "$APP_NAME" =~ [/\*\|\&\;] ]]; then
    log_error "APP_NAME inválido: caracteres especiais não são permitidos."
    exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o BatchMode=yes)
if [[ -n "$SSH_KEY_FILE" ]]; then
    [[ ! -f "$SSH_KEY_FILE" ]] && { log_error "Chave SSH não encontrada: $SSH_KEY_FILE"; exit 1; }
    SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

log "🔧 Configuração de redirecionamento Apache2 para '$APP_NAME' → $REDIRECT_SERVER_IP"

# Parse mappings (suporta newline ou vírgula como separador)
mapfile -t MAPPINGS_RAW <<< "$REDIRECT_MAPPINGS"
if [[ ${#MAPPINGS_RAW[@]} -eq 1 && "$REDIRECT_MAPPINGS" == *","* ]]; then
    IFS=',' read -r -a MAPPINGS_RAW <<< "$REDIRECT_MAPPINGS"
fi

declare -a CONFIG_LINES
log "📋 Processando mapeamentos:"
for mapping in "${MAPPINGS_RAW[@]}"; do
    mapping="${mapping#"${mapping%%[![:space:]]*}"}"  # ltrim
    mapping="${mapping%"${mapping##*[![:space:]]}"}"  # rtrim
    [[ -z "$mapping" ]] && continue

    IFS=':' read -r nome_servidor tomcat alias_redirecionamento <<< "$mapping"
    nome_servidor="${nome_servidor// /}"
    tomcat="${tomcat// /}"
    alias_redirecionamento="${alias_redirecionamento// /}"

    if [[ -z "$nome_servidor" || -z "$tomcat" || -z "$alias_redirecionamento" ]]; then
        log_warn "Mapeamento inválido ignorado: '$mapping'. Formato: nome_servidor:tomcat:alias"
        continue
    fi

    config_line="/${APP_NAME}*=${alias_redirecionamento}"
    CONFIG_LINES+=("$config_line")
    log "  → $nome_servidor:$tomcat → $config_line"
done

if [[ ${#CONFIG_LINES[@]} -eq 0 ]]; then
    log_error "Nenhum mapeamento válido encontrado. Abortando."
    exit 1
fi

REMOTE_TMP_PREFIX="/tmp/${APP_NAME}_redirect_${RANDOM}_$$"
CONFIG_FILE="${REMOTE_TMP_PREFIX}/uriworkermap_updates.txt"

log "📤 Enviando configuração e executando no servidor Apache2"

# Unifica mkdir + envio do arquivo em uma única conexão SSH
printf '%s\n' "${CONFIG_LINES[@]}" | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REDIRECT_SERVER_IP}" \
    "mkdir -p '${REMOTE_TMP_PREFIX}' && cat > '${CONFIG_FILE}'"

# Executa a configuração remota
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REDIRECT_SERVER_IP}" "bash -s" \
    -- "$SUDO_PASSWORD" "$APP_NAME" "$REMOTE_TMP_PREFIX" << 'ENDSSH'
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
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
}

echo "[REMOTE] 🔧 Iniciando configuração de redirecionamento para $APP_NAME"

run_sudo mkdir -p "$BACKUP_DIR"

# Backup
if run_sudo test -f "$URIWORKERMAP_FILE"; then
    echo "[REMOTE] 📦 Backup: $BACKUP_FILE"
    run_sudo cp "$URIWORKERMAP_FILE" "$BACKUP_FILE"
    # Mantém os últimos 5 backups
    run_sudo bash -c "ls -t '${BACKUP_DIR}/uriworkermap.properties.'* 2>/dev/null | tail -n +6 | xargs -r rm -f" || true
else
    echo "[REMOTE] 📄 Arquivo não existe, será criado"
    run_sudo touch "$URIWORKERMAP_FILE"
fi

EXISTING_CONTENT=$(run_sudo cat "$URIWORKERMAP_FILE")
UPDATED_CONTENT="$EXISTING_CONTENT"
CHANGED=false

while IFS= read -r config_line; do
    [[ -z "$config_line" ]] && continue

    # Escapa caracteres especiais do key para uso seguro no sed
    key=$(printf '%s' "$config_line" | cut -d'=' -f1)
    escaped_key=$(printf '%s' "$key" | sed 's/[]\/$*.^[]/\\&/g')
    escaped_line=$(printf '%s' "$config_line" | sed 's/[\/&]/\\&/g')

    if printf '%s\n' "$EXISTING_CONTENT" | grep -q "^${escaped_key}="; then
        echo "[REMOTE] 📝 Atualizando: $config_line"
        UPDATED_CONTENT=$(printf '%s\n' "$UPDATED_CONTENT" | sed "s|^${escaped_key}=.*|${escaped_line}|")
        CHANGED=true
    else
        echo "[REMOTE] ➕ Adicionando: $config_line"
        UPDATED_CONTENT=$(printf '%s\n%s' "$UPDATED_CONTENT" "$config_line")
        CHANGED=true
    fi
done < "$CONFIG_FILE"

if [[ "$CHANGED" != "true" ]]; then
    echo "[REMOTE] ℹ️ Nenhuma alteração necessária"
    rm -rf "$REMOTE_TMP_PREFIX"
    exit 0
fi

# Valida o resultado final em cópia temporária antes de tocar no arquivo original
TEMP_VALIDATE_FILE="${REMOTE_TMP_PREFIX}/uriworkermap_validate.properties"
printf '%s\n' "$UPDATED_CONTENT" > "$TEMP_VALIDATE_FILE"

if [[ ! -s "$TEMP_VALIDATE_FILE" ]]; then
    echo "[REMOTE] ❌ ERRO: Conteúdo resultante está vazio. Abortando sem modificar o arquivo original." >&2
    rm -rf "$REMOTE_TMP_PREFIX"
    exit 1
fi

echo "[REMOTE] 💾 Aplicando alterações diretamente no arquivo original"

restore_backup() {
    echo "[REMOTE] 🔄 Restaurando backup: $BACKUP_FILE" >&2
    run_sudo cp "$BACKUP_FILE" "$URIWORKERMAP_FILE"
    rm -rf "$REMOTE_TMP_PREFIX"
    exit 1
}

# Re-processa o CONFIG_FILE aplicando cirurgicamente no arquivo original:
# - linhas existentes: sed in-place (não recria o arquivo)
# - linhas novas: append com tee -a (nunca sobrescreve)
# Valida antes e depois de cada operação que a contagem de linhas é a esperada
while IFS= read -r config_line; do
    [[ -z "$config_line" ]] && continue

    key=$(printf '%s' "$config_line" | cut -d'=' -f1)
    escaped_key=$(printf '%s' "$key" | sed 's/[]\/$*.^[]/\\&/g')
    escaped_line=$(printf '%s' "$config_line" | sed 's/[\/&]/\\&/g')

    LINES_BEFORE=$(run_sudo wc -l < "$URIWORKERMAP_FILE")

    if run_sudo grep -q "^${escaped_key}=" "$URIWORKERMAP_FILE"; then
        echo "[REMOTE] 📝 Atualizando (sed in-place): $config_line"
        run_sudo sed -i "s|^${escaped_key}=.*|${escaped_line}|" "$URIWORKERMAP_FILE"
        LINES_EXPECTED=$LINES_BEFORE
    else
        echo "[REMOTE] ➕ Adicionando ao fim: $config_line"
        printf '%s\n' "$config_line" | run_sudo tee -a "$URIWORKERMAP_FILE" > /dev/null
        LINES_EXPECTED=$((LINES_BEFORE + 1))
    fi

    LINES_AFTER=$(run_sudo wc -l < "$URIWORKERMAP_FILE")
    if [[ "$LINES_AFTER" -ne "$LINES_EXPECTED" ]]; then
        echo "[REMOTE] ❌ ERRO: Contagem de linhas inesperada após operação em '$config_line'." >&2
        echo "[REMOTE]    Esperado: $LINES_EXPECTED | Obtido: $LINES_AFTER" >&2
        restore_backup
    fi
    echo "[REMOTE] ✔ Linhas no arquivo: $LINES_AFTER (esperado: $LINES_EXPECTED)"
done < "$CONFIG_FILE"

# Validação pós-escrita: arquivo não pode estar vazio
if [[ $(run_sudo wc -c < "$URIWORKERMAP_FILE" 2>/dev/null || echo 0) -eq 0 ]]; then
    echo "[REMOTE] ❌ ERRO: Arquivo ficou vazio após escrita!" >&2
    restore_backup
fi

# Reload Apache2
echo "[REMOTE] 🔄 Recarregando Apache2"
if run_sudo systemctl reload apache2; then
    echo "[REMOTE] ✅ Apache2 recarregado (systemctl)"
elif run_sudo service apache2 reload; then
    echo "[REMOTE] ✅ Apache2 recarregado (service)"
else
    echo "[REMOTE] ❌ ERRO: Falha ao recarregar Apache2. Restaurando backup..." >&2
    run_sudo cp "$BACKUP_FILE" "$URIWORKERMAP_FILE"
    echo "[REMOTE] 🔄 Backup restaurado: $BACKUP_FILE"
    rm -rf "$REMOTE_TMP_PREFIX"
    exit 1
fi

rm -rf "$REMOTE_TMP_PREFIX"
echo "[REMOTE] ✅ Configuração de redirecionamento concluída"
ENDSSH

log_success "Redirecionamento Apache2 configurado para '$APP_NAME' em $REDIRECT_SERVER_IP"

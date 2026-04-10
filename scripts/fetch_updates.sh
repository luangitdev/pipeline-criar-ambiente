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

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

TIPO_AMBIENTE=""
REPO_URL=""
REPO_BRANCH=""
WORK_DIR=""
OUTPUT_DIR=""
GIT_USERNAME=""
GIT_TOKEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tipo-ambiente)
            TIPO_AMBIENTE="$2"
            shift 2
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --repo-branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --git-username)
            GIT_USERNAME="$2"
            shift 2
            ;;
        --git-token)
            GIT_TOKEN="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$TIPO_AMBIENTE" || -z "$REPO_URL" || -z "$REPO_BRANCH" || -z "$WORK_DIR" || -z "$OUTPUT_DIR" ]]; then
    log_error "Parâmetros obrigatórios faltando!"
    exit 1
fi

TIPO_AMBIENTE=$(echo "$TIPO_AMBIENTE" | tr '[:upper:]' '[:lower:]')
if [[ "$TIPO_AMBIENTE" != "ptf" && "$TIPO_AMBIENTE" != "pln" ]]; then
    log_error "Tipo de ambiente inválido: $TIPO_AMBIENTE (esperado: ptf ou pln)"
    exit 1
fi

if [[ -z "$GIT_USERNAME" || -z "$GIT_TOKEN" ]]; then
    log_error "Credenciais Git não informadas"
    exit 1
fi

CLONE_DIR="$WORK_DIR/infraestrutura"
mkdir -p "$WORK_DIR"
rm -rf "$CLONE_DIR"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.sql

ASKPASS_SCRIPT="$WORK_DIR/git-askpass.sh"
cat > "$ASKPASS_SCRIPT" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) echo "$GIT_USERNAME" ;;
  *Password*) echo "$GIT_TOKEN" ;;
  *) echo "" ;;
esac
EOF
chmod 700 "$ASKPASS_SCRIPT"

cleanup() {
    rm -f "$ASKPASS_SCRIPT"
}
trap cleanup EXIT

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS="$ASKPASS_SCRIPT"
export GIT_USERNAME
export GIT_TOKEN

log "🔄 Clonando repositório de migrations..."
git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR" >/dev/null 2>&1
log_success "Repositório clonado em: $CLONE_DIR"

find_updates_root() {
    find "$CLONE_DIR" -maxdepth 3 -type d \
        \( -iname "Atualizações de banco" -o -iname "Atualizacoes de banco" -o -iname "Atualizacoes banco" -o -iname "*atualiza*de*ban*" \) \
        | head -n1
}

find_env_dir() {
    local base_dir="$1"
    local env="$2"

    if [[ "$env" == "ptf" ]]; then
        find "$base_dir" -mindepth 1 -maxdepth 2 -type d -iname "*pathfind*" | head -n1
    else
        find "$base_dir" -mindepth 1 -maxdepth 2 -type d -iname "*planner*" | head -n1
    fi
}

UPDATES_ROOT=$(find_updates_root || true)
if [[ -z "${UPDATES_ROOT:-}" ]]; then
    log_error "Pasta de atualizações não encontrada no repositório"
    exit 1
fi

SOURCE_DIR=$(find_env_dir "$UPDATES_ROOT" "$TIPO_AMBIENTE" || true)
if [[ -z "${SOURCE_DIR:-}" ]]; then
    log_error "Pasta de updates do ambiente '$TIPO_AMBIENTE' não encontrada em '$UPDATES_ROOT'"
    exit 1
fi

log "📁 Origem dos updates: $SOURCE_DIR"

copied=0
while IFS= read -r -d '' sql_file; do
    base_file="$(basename "$sql_file")"
    target_file="$OUTPUT_DIR/$base_file"

    if [[ -f "$target_file" ]]; then
        log_error "Arquivo SQL duplicado detectado: $base_file"
        exit 1
    fi

    cp "$sql_file" "$target_file"
    copied=$((copied + 1))
done < <(find "$SOURCE_DIR" -type f -name "*.sql" -print0)

if [[ "$copied" -eq 0 ]]; then
    log_warning "Nenhum arquivo .sql encontrado na origem: $SOURCE_DIR"
else
    log_success "$copied arquivos SQL copiados para: $OUTPUT_DIR"
fi


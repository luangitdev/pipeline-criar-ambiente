#!/bin/bash

# Script para verificar se o banco de dados foi criado corretamente

set -euo pipefail

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
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

# Parse argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --nome-banco)
            NOME_BANCO="$2"
            shift 2
            ;;
        --db-host)
            DB_HOST="$2"
            shift 2
            ;;
        --db-port)
            DB_PORT="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

log "🔍 Verificando banco de dados: $NOME_BANCO"

# Configurar conexão (assumindo que o bastion host já tem acesso direto ao DB)
TUNNEL_PID=""
EFFECTIVE_HOST="$DB_HOST"
EFFECTIVE_PORT="$DB_PORT"

log "🔗 Configuração de conexão: $EFFECTIVE_HOST:$EFFECTIVE_PORT"

# Função para executar SQL
execute_sql() {
    local sql="$1"
    local database="${2:-$NOME_BANCO}"
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -t -c "$sql" | xargs
}

# Primeiro testar conexão com o servidor
log "🔍 Testando conexão com o servidor PostgreSQL..."
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d postgres -c "SELECT 1;" &>/dev/null; then
    log_error "Falha ao conectar com o servidor PostgreSQL em $EFFECTIVE_HOST:$EFFECTIVE_PORT (original: $DB_HOST:$DB_PORT)"
    log_error "Verifique se o servidor está rodando e acessível"
    
    # Limpar tunnel se criado
    if [[ -n "$TUNNEL_PID" ]]; then
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    exit 1
fi
log_success "Conexão com o servidor estabelecida"

# Verificar se banco existe
log "📄 Verificando existência do banco..."
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$NOME_BANCO';" | grep -q 1; then
    log_error "Banco $NOME_BANCO não encontrado!"
    exit 1
fi
log_success "Banco $NOME_BANCO existe"

# Verificar conectividade específica do banco
log "🔗 Testando conectividade com o banco..."
if ! result=$(PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -t -c "SELECT 'OK' as status;" 2>/dev/null | xargs); then
    log_error "Erro ao conectar no banco $NOME_BANCO"
    exit 1
fi

if [[ "$result" != "OK" ]]; then
    log_error "Falha na conectividade com o banco"
    exit 1
fi
log_success "Conectividade com o banco OK"

# Verificar tabelas essenciais
log "📋 Verificando tabelas essenciais..."
TABELAS=("configuracao" "empresa" "usuario")
for tabela in "${TABELAS[@]}"; do
    if count=$(execute_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='$tabela';"); then
        if [[ "$count" -gt 0 ]]; then
            log_success "Tabela $tabela existe"
        else
            log_error "Tabela $tabela não encontrada!"
            exit 1
        fi
    fi
done

# Verificar versão
log "📊 Verificando versão do banco..."
if versao=$(execute_sql "SELECT valor_texto FROM configuracao WHERE nomecampo = 'versao_banco';" 2>/dev/null || echo "N/A"); then
    log_success "Versão do banco: $versao"
else
    log "Versão não encontrada (pode ser normal)"
fi

# Conexão finalizada

log_success "✅ Verificação do banco concluída com sucesso!"
#!/bin/bash

# Script principal para criação de banco de dados
# Baseado na lógica do Ansible, mas adaptado para execução direta

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
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

# Variáveis padrão
TIPO_AMBIENTE=""
SERVIDOR=""
NOME_BANCO=""
VERSAO_DESEJADA=""
DB_HOST=""
DB_PORT="5432"
DB_USER=""
DB_PASSWORD=""
WORKSPACE=""

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --tipo-ambiente)
            TIPO_AMBIENTE="$2"
            shift 2
            ;;
        --servidor)
            SERVIDOR="$2"
            shift 2
            ;;
        --nome-banco)
            NOME_BANCO="$2"
            shift 2
            ;;
        --versao-desejada)
            VERSAO_DESEJADA="$2"
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
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

# Validações
if [[ -z "$TIPO_AMBIENTE" || -z "$NOME_BANCO" || -z "$DB_HOST" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    log_error "Parâmetros obrigatórios faltando!"
    exit 1
fi

log "🚀 INICIANDO CRIAÇÃO DO BANCO DE DADOS"
log "📋 Configuração:"
log "   - Ambiente: $TIPO_AMBIENTE"
log "   - Servidor: $SERVIDOR"
log "   - Banco: $NOME_BANCO"
log "   - Host: $DB_HOST:$DB_PORT"
log "   - Versão: $VERSAO_DESEJADA"

# Definir template baseado no ambiente
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    TEMPLATE_DB="ptf_banco_limpo_v15_12_0_3_43"
else
    TEMPLATE_DB="ptf_planner_banco_limpo_9_0_0_0_0"
fi

# Permitir override via variável de ambiente (se necessário)
TEMPLATE_DB="${TEMPLATE_DB_OVERRIDE:-$TEMPLATE_DB}"

log "📋 Template obrigatório: $TEMPLATE_DB"

# Função para executar SQL
execute_sql() {
    local sql="$1"
    local database="${2:-postgres}"
    
    if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -c "$sql"; then
        log_error "Falha ao executar comando SQL: $sql"
        return 1
    fi
    return 0
}

# Função para executar arquivo SQL
execute_sql_file() {
    local file="$1"
    local database="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "Arquivo SQL não encontrado: $file"
        return 1
    fi
    
    log "📄 Executando: $(basename "$file")"
    if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -f "$file"; then
        log_error "Falha ao executar o arquivo SQL: $(basename "$file")"
        return 1
    fi
    return 0
}

# Configurar conexão (assumindo que o bastion host já tem acesso direto ao DB)
EFFECTIVE_HOST="$DB_HOST"
EFFECTIVE_PORT="$DB_PORT"

log "🔗 Configuração de conexão: $EFFECTIVE_HOST:$EFFECTIVE_PORT"

# 1. Testar conexão com o banco antes de prosseguir
log "🔍 Testando conexão com o servidor de banco..."
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d postgres -c "SELECT 1;" &>/dev/null; then
    log_error "Falha ao conectar com o servidor PostgreSQL em $EFFECTIVE_HOST:$EFFECTIVE_PORT (original: $DB_HOST:$DB_PORT)"
    log_error "Verifique se o servidor está rodando e acessível"
    
    # Limpar tunnel se criado
    if [[ -n "$TUNNEL_PID" ]]; then
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    exit 1
fi
log_success "Conexão com o servidor estabelecida com sucesso!"

# 2. Verificar se template existe (obrigatório)
log "🔍 Verificando se template existe: $TEMPLATE_DB"
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$TEMPLATE_DB"; then
    log_error "❌ Template '$TEMPLATE_DB' não encontrado no servidor $EFFECTIVE_HOST:$EFFECTIVE_PORT"
    log_error "📋 Bancos disponíveis no servidor:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -v "^$" | sort | head -20
    log_error "💡 Certifique-se de que o template '$TEMPLATE_DB' existe no servidor de destino"
    exit 1
fi
log_success "Template $TEMPLATE_DB encontrado!"

# 3. Criar banco de dados com template
log "🗄️ Criando banco com template: $TEMPLATE_DB"
if execute_sql "CREATE DATABASE \"$NOME_BANCO\" WITH TEMPLATE \"$TEMPLATE_DB\";" 2>/dev/null; then
    log_success "Banco $NOME_BANCO criado com sucesso!"
else
    # Verificar se o banco já existe
    if PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$NOME_BANCO"; then
        log_warning "Banco $NOME_BANCO já existe, continuando..."
    else
        log_error "Falha ao criar o banco $NOME_BANCO"
        log_error "Verifique se o usuário tem permissões para criar bancos"
        exit 1
    fi
fi

# 2. Processar dados do ambiente
log "📋 Processando dados do ambiente..."
DADOS_FILE="$WORKSPACE/dados/$TIPO_AMBIENTE/dados.txt"
if [[ -f "$DADOS_FILE" ]]; then
    # Gerar start.sql personalizado
    "$WORKSPACE/scripts/generate_start_sql.sh" "$DADOS_FILE" "$TIPO_AMBIENTE" "$WORKSPACE/temp"
else
    log_warning "Arquivo de dados não encontrado: $DADOS_FILE"
fi

# 3. Executar configuração inicial (start.sql)
START_SQL="$WORKSPACE/temp/start_${TIPO_AMBIENTE}.sql"
if [[ -f "$START_SQL" ]]; then
    log "🔧 Executando configuração inicial..."
    execute_sql_file "$START_SQL" "$NOME_BANCO"
    log_success "Configuração inicial aplicada"
else
    log_warning "Arquivo start.sql não encontrado"
fi

# 4. Executar scripts de configuração (config.sql)
CONFIG_SQL="$WORKSPACE/sql/$TIPO_AMBIENTE/config.sql"
if [[ -f "$CONFIG_SQL" && "$TIPO_AMBIENTE" != "pln" ]]; then
    log "⚙️ Executando scripts de configuração..."
    execute_sql_file "$CONFIG_SQL" "$NOME_BANCO"
    log_success "Scripts de configuração aplicados"
fi

# 5. Obter versão atual do banco
log "📊 Verificando versão atual do banco..."
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    VERSAO_ATUAL=$(PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -t -c "SELECT valor_texto FROM configuracao WHERE nomecampo = 'versao_banco';" | xargs || echo "0.0.0.0-0")
else
    VERSAO_ATUAL=$(PGPASSWORD="$DB_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -t -c "SELECT versao FROM versaobanco ORDER BY id DESC LIMIT 1;" | xargs || echo "0.0.0.0-0")
fi

log "📋 Versão atual: $VERSAO_ATUAL"

# 6. Executar updates necessários
log "🔄 Executando updates necessários..."
UPDATES_DIR="$WORKSPACE/sql/$TIPO_AMBIENTE/updates"
if [[ -d "$UPDATES_DIR" ]]; then
    UPDATE_COUNT=0
    
    # Ordenar arquivos por versão
    for update_file in $(ls -1v "$UPDATES_DIR"/*.sql 2>/dev/null || true); do
        if [[ -f "$update_file" ]]; then
            update_version=$(basename "$update_file" .sql)
            
            # Verificar se update deve ser aplicado
            if [[ "$update_version" > "$VERSAO_ATUAL" ]] && [[ "$update_version" <= "$VERSAO_DESEJADA" ]]; then
                log "🔄 Aplicando update: $update_version"
                if execute_sql_file "$update_file" "$NOME_BANCO"; then
                    ((UPDATE_COUNT++))
                    log_success "Update $update_version aplicado"
                else
                    log_error "Falha ao aplicar update $update_version"
                    exit 1
                fi
            fi
        fi
    done
    
    log_success "$UPDATE_COUNT updates aplicados"
else
    log_warning "Diretório de updates não encontrado: $UPDATES_DIR"
fi

# 7. Executar credenciais
CREDENTIALS_SQL="$WORKSPACE/sql/$TIPO_AMBIENTE/credentials.sql"
if [[ -f "$CREDENTIALS_SQL" ]]; then
    log "🔐 Aplicando credenciais..."
    if execute_sql_file "$CREDENTIALS_SQL" "$NOME_BANCO"; then
        log_success "Credenciais aplicadas com sucesso"
    else
        log_warning "Erro ao aplicar credenciais (pode ser normal se usuários já existem)"
    fi
fi

# Conexão finalizada

log_success "🎉 Criação do banco de dados concluída com sucesso!"
log "📋 Resumo:"
log "   - Banco: $NOME_BANCO"
log "   - Versão inicial: $VERSAO_ATUAL"
log "   - Versão final: $VERSAO_DESEJADA"
log "   - Updates aplicados: $UPDATE_COUNT"
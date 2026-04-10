#!/bin/bash

# Script principal para criação de banco de dados
# Baseado na lógica do Ansible, mas adaptado para execução direta

set -uo pipefail  # Removido -e para permitir tratamento manual de erros

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
UPDATES_DIR_OVERRIDE=""

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
        --updates-dir)
            UPDATES_DIR_OVERRIDE="$2"
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

# Proteger senha contra expansão usando base64 encoding
DB_PASSWORD_ENCODED=$(echo -n "$DB_PASSWORD" | base64)
log "🔧 Senha codificada em base64 para evitar expansão de caracteres especiais"

# Função para comparar versões numericamente
# Retorna: 0 se v1 == v2, 1 se v1 > v2, -1 se v1 < v2
compare_versions() {
    local v1="$1"
    local v2="$2"
    
    # Se as versões são iguais
    if [[ "$v1" == "$v2" ]]; then
        echo "0"
        return
    fi
    
    # Usar sort com versão numérica para comparar
    local sorted=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V)
    local first_line=$(echo "$sorted" | head -n1)
    
    if [[ "$first_line" == "$v1" ]]; then
        echo "-1"  # v1 < v2
    else
        echo "1"   # v1 > v2
    fi
}

# Função para executar psql com senha segura
run_psql_safe() {
    local password_decoded=$(echo "$DB_PASSWORD_ENCODED" | base64 -d)
    PGPASSWORD="$password_decoded" "$@"
}

log "🚀 INICIANDO CRIAÇÃO DO BANCO DE DADOS"
log "📋 Configuração:"
log "   - Ambiente: $TIPO_AMBIENTE"
log "   - Servidor: $SERVIDOR"
log "   - Banco: $NOME_BANCO"
log "   - Host: $DB_HOST:$DB_PORT"
log "   - Versão: $VERSAO_DESEJADA"
if [[ -n "$UPDATES_DIR_OVERRIDE" ]]; then
    log "   - Updates dir (override): $UPDATES_DIR_OVERRIDE"
fi

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
    local database="${2:-$TEMPLATE_DB}"  # Usar template como padrão em vez de 'postgres'
    
    if ! run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -c "$sql"; then
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
    
    # Executar SQL capturando erros mas não falhando se for erro de dados
    if ! SQL_OUTPUT=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -f "$file" 2>&1); then
        # Se contém erros de schema/dados, avisar mas continuar
        if echo "$SQL_OUTPUT" | grep -q "does not exist\|already exists\|duplicate key"; then
            log_warning "Avisos SQL em $(basename "$file"):"
            echo "$SQL_OUTPUT" | grep "ERROR\|WARNING" || true
            log_warning "Continuando execução (erros de dados/schema podem ser normais)"
            return 0
        else
            # Outros erros são críticos
            log_error "Falha crítica ao executar $(basename "$file"):"
            echo "$SQL_OUTPUT"
            return 1
        fi
    fi
    return 0
}

# Configurar conexão (assumindo que o bastion host já tem acesso direto ao DB)
EFFECTIVE_HOST="$DB_HOST"
EFFECTIVE_PORT="$DB_PORT"

# Inicializar variável de túnel SSH (mesmo que não usado)
TUNNEL_PID=""

# Template baseado no tipo de ambiente
if [[ "$TIPO_AMBIENTE" == "pln" ]]; then
    TEMPLATE_HOST="10.200.0.3"    # GCP-PLN
    TEMPLATE_SERVER_NAME="GCP-PLN"
else
    TEMPLATE_HOST="10.200.0.19"   # GCP01 (PTF padrão)
    TEMPLATE_SERVER_NAME="GCP01"
fi
TEMPLATE_PORT="5432"

log "🔗 Configuração de conexão:"
log "   - Servidor destino: $EFFECTIVE_HOST:$EFFECTIVE_PORT" 
log "   - Template source: $TEMPLATE_HOST:$TEMPLATE_PORT ($TEMPLATE_SERVER_NAME)"

# 1. Verificar ambiente e ferramentas
log "🔧 Verificando ambiente de execução..."
log "   - Usuário: $(whoami)"
log "   - Sistema: $(uname -a)"
log "   - PostgreSQL client: $(which psql 2>/dev/null || echo 'NÃO ENCONTRADO')"

if ! command -v psql &> /dev/null; then
    log_error "PostgreSQL client (psql) não está disponível no bastion host!"
    log_error "Verifique se o postgresql-client está instalado no bastion"
    exit 1
fi

log_success "PostgreSQL client encontrado: $(which psql)"

# 2. Testar conexão com o banco antes de prosseguir
log "🔍 Testando conexão com o servidor de banco..."
log "🔧 Comando: psql -h $EFFECTIVE_HOST -p $EFFECTIVE_PORT -U $DB_USER -d $TEMPLATE_DB -c \"SELECT 1;\""

# Usar template database para teste pois usuário pode não ter acesso ao 'postgres'
# Capturar erro específico usando função segura
PSQL_ERROR=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "SELECT 1;" 2>&1)
PSQL_EXIT_CODE=$?

if [ $PSQL_EXIT_CODE -ne 0 ]; then
    log_error "Falha ao conectar com o servidor PostgreSQL em $EFFECTIVE_HOST:$EFFECTIVE_PORT"
    log_error "Erro específico: $PSQL_ERROR"
    log_error ""
    log_error "Verifique se:"
    log_error "  1. O servidor PostgreSQL está rodando"
    log_error "  2. O bastion host tem acesso à rede privada"
    log_error "  3. As credenciais estão corretas (usuário: $DB_USER)"
    log_error "  4. A porta $EFFECTIVE_PORT está aberta"
    log_error "  5. O template '$TEMPLATE_DB' existe"
    
    # Limpar tunnel se criado
    if [[ -n "${TUNNEL_PID:-}" ]]; then
        kill "$TUNNEL_PID" 2>/dev/null || true
    fi
    exit 1
fi
log_success "Conexão com o servidor estabelecida com sucesso!"

# 2. Verificar se template existe no servidor de template
log "🔍 Verificando se template existe no $TEMPLATE_SERVER_NAME: $TEMPLATE_DB"
# Conectar no próprio template para verificar se existe e se temos acesso
if ! run_psql_safe psql -h "$TEMPLATE_HOST" -p "$TEMPLATE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "SELECT 1;" &>/dev/null; then
    log_error "❌ Template '$TEMPLATE_DB' não encontrado ou sem acesso no servidor $TEMPLATE_HOST:$TEMPLATE_PORT ($TEMPLATE_SERVER_NAME)"
    log_error "💡 Verifique se:"
    log_error "   - O template '$TEMPLATE_DB' existe no $TEMPLATE_SERVER_NAME"
    log_error "   - O usuário '$DB_USER' tem acesso ao template"
    exit 1
fi
log_success "Template $TEMPLATE_DB encontrado no $TEMPLATE_SERVER_NAME!"

# 3. Criar banco de dados copiando template do GCP01
log "🗄️ Criando banco $NOME_BANCO no servidor de destino..."

# Primeiro verificar se o banco já existe no destino
# Conectar no template para fazer a verificação
if run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "\l" | grep -qw "$NOME_BANCO"; then
    log_warning "Banco $NOME_BANCO já existe no servidor de destino, continuando..."
else
    # Criar banco vazio no destino
    log "📄 Criando banco vazio no destino..."
    if ! execute_sql "CREATE DATABASE \"$NOME_BANCO\";" 2>/dev/null; then
        log_error "Falha ao criar banco vazio $NOME_BANCO no servidor de destino"
        exit 1
    fi
    log_success "Banco vazio criado no destino!"
    
    # Copiar dados do template via pg_dump/pg_restore
    log "📋 Copiando dados do template $TEMPLATE_DB ($TEMPLATE_SERVER_NAME → destino)..."
    DUMP_FILE="/tmp/template_dump_$$.sql"
    
    # Fazer dump do template no servidor de origem
    log "📤 Fazendo dump do template..."
    if ! run_psql_safe pg_dump -h "$TEMPLATE_HOST" -p "$TEMPLATE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" > "$DUMP_FILE"; then
        log_error "Falha ao fazer dump do template $TEMPLATE_DB"
        rm -f "$DUMP_FILE"
        exit 1
    fi
    
    # Restaurar no banco de destino
    log "📥 Restaurando dados no banco de destino..."
    if ! run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" < "$DUMP_FILE"; then
        log_error "Falha ao restaurar dados no banco $NOME_BANCO"
        rm -f "$DUMP_FILE"
        exit 1
    fi
    
    # Limpar arquivo temporário
    rm -f "$DUMP_FILE"
    log_success "Banco $NOME_BANCO criado com dados do template!"
fi

# 2. Processar dados do ambiente
log "📋 Processando dados do ambiente..."
# Priorizar arquivo temporário criado pelo Jenkins (parâmetro)
DADOS_FILE_TEMP="$WORKSPACE/temp/dados.txt"
DADOS_FILE_DEFAULT="$WORKSPACE/dados/$TIPO_AMBIENTE/dados.txt"

if [[ -f "$DADOS_FILE_TEMP" ]]; then
    log "📄 Usando dados fornecidos como parâmetro"
    DADOS_FILE="$DADOS_FILE_TEMP"
elif [[ -f "$DADOS_FILE_DEFAULT" ]]; then
    log "📄 Usando arquivo padrão do ambiente"  
    DADOS_FILE="$DADOS_FILE_DEFAULT"
else
    log_error "❌ Nenhum arquivo de dados encontrado!"
    log_error "   Esperado: $DADOS_FILE_TEMP ou $DADOS_FILE_DEFAULT"
    exit 1
fi

# Gerar start.sql personalizado
"$WORKSPACE/scripts/generate_start_sql.sh" "$DADOS_FILE" "$TIPO_AMBIENTE" "$WORKSPACE/temp"

# 3. Executar configuração inicial (start.sql)
START_SQL="$WORKSPACE/temp/start_${TIPO_AMBIENTE}.sql"
if [[ -f "$START_SQL" ]]; then
    log "🔧 Executando configuração inicial..."
    if execute_sql_file "$START_SQL" "$NOME_BANCO"; then
        log_success "Configuração inicial aplicada"
    else
        log_error "Falha ao aplicar configuração inicial"
        exit 1
    fi
else
    log_warning "Arquivo start.sql não encontrado: $START_SQL"
    log "🔍 Listando conteúdo de temp/:"
    ls -la "$WORKSPACE/temp/" || log_warning "Diretório temp não existe"
fi

# 4. Executar scripts de configuração (config.sql)
CONFIG_SQL="$WORKSPACE/sql/$TIPO_AMBIENTE/config.sql"
if [[ -f "$CONFIG_SQL" && "$TIPO_AMBIENTE" != "pln" ]]; then
    log "⚙️ Executando scripts de configuração..."
    if execute_sql_file "$CONFIG_SQL" "$NOME_BANCO"; then
        log_success "Scripts de configuração aplicados"
    else
        log_error "Falha ao aplicar configuração"
        exit 1
    fi
else
    if [[ "$TIPO_AMBIENTE" == "pln" ]]; then
        log "ℹ️ Config.sql ignorado para ambiente PLN"
    else
        log_warning "Arquivo config.sql não encontrado: $CONFIG_SQL"
    fi
fi

# 5. Obter versão atual do banco
log "📊 Verificando versão atual do banco..."
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    VERSAO_ATUAL=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -t -c "SELECT valor_texto FROM configuracao WHERE nomecampo = 'versao_banco';" | xargs || echo "0.0.0.0-0")
else
    VERSAO_ATUAL=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -t -c "SELECT versao FROM versaobanco ORDER BY id DESC LIMIT 1;" | xargs || echo "0.0.0.0-0")
fi

log "📋 Versão atual: $VERSAO_ATUAL"

# 6. Executar updates necessários
log "🔄 Executando updates necessários..."
UPDATES_DIR="${UPDATES_DIR_OVERRIDE:-$WORKSPACE/sql/$TIPO_AMBIENTE/updates}"
if [[ -d "$UPDATES_DIR" ]]; then
    log "📁 Arquivos encontrados em updates:"
    ls -la "$UPDATES_DIR/" || log_warning "Erro ao listar updates"
    UPDATE_COUNT=0
    
    # Ordenar arquivos por versão
    for update_file in $(ls -1v "$UPDATES_DIR"/*.sql 2>/dev/null || true); do
        if [[ -f "$update_file" ]]; then
            update_version=$(basename "$update_file" .sql)
            
            # Verificar se update deve ser aplicado usando comparação numérica de versões
            # Condição: versão do update > versão atual E versão do update <= versão desejada
            comp_atual=$(compare_versions "$update_version" "$VERSAO_ATUAL")
            comp_desejada=$(compare_versions "$update_version" "$VERSAO_DESEJADA")
            
            # update_version > VERSAO_ATUAL AND update_version <= VERSAO_DESEJADA
            if [[ "$comp_atual" == "1" ]] && [[ "$comp_desejada" == "-1" || "$comp_desejada" == "0" ]]; then
                log "🔄 Aplicando update: $update_version (atual: $VERSAO_ATUAL, desejada: $VERSAO_DESEJADA)"
                if execute_sql_file "$update_file" "$NOME_BANCO"; then
                    ((UPDATE_COUNT++))
                    log_success "Update $update_version aplicado"
                else
                    log_error "Falha ao aplicar update $update_version"
                    exit 1
                fi
            else
                log "⏭️ Pulando update $update_version (fora do intervalo: $VERSAO_ATUAL < x <= $VERSAO_DESEJADA)"
                log "🔍 DEBUG: comp_atual=$comp_atual, comp_desejada=$comp_desejada"
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

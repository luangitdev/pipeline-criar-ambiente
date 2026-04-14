#!/bin/bash

# Script principal para criação de banco de dados
# Baseado na lógica do Ansible, mas adaptado para execução direta

set -uo pipefail  # Removido -e para permitir tratamento manual de erros

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log_utils.sh"

# Variáveis padrão
TIPO_AMBIENTE=""
SERVIDOR=""
NOME_BANCO=""
VERSAO_BANCO=""
DB_HOST=""
DB_PORT="5432"
DB_USER=""
DB_PASSWORD=""
WORKSPACE=""
UPDATES_DIR_OVERRIDE=""
ALLOW_EXISTING_DB="${ALLOW_EXISTING_DB:-false}"

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
        --versao-banco|--versao-desejada)
            VERSAO_BANCO="$2"
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

# Extrai versão no formato N.N.N.N-N de um texto (ex.: nome de arquivo)
extract_version_token() {
    local text="$1"
    if [[ "$text" =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Função para executar psql com senha segura
run_psql_safe() {
    local password_decoded=$(echo "$DB_PASSWORD_ENCODED" | base64 -d)
    PGPASSWORD="$password_decoded" "$@"
}

log "🚀 Criando banco '$NOME_BANCO' [$TIPO_AMBIENTE] em $DB_HOST:$DB_PORT — versão alvo: $VERSAO_BANCO"

if ! normalized_desired_version=$(extract_version_token "$VERSAO_BANCO"); then
    log_error "Versão de banco inválida: '$VERSAO_BANCO' (esperado formato N.N.N.N-N)"
    exit 1
fi
VERSAO_BANCO="$normalized_desired_version"

# Definir template baseado no ambiente
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    TEMPLATE_DB="ptf_banco_limpo_v15_12_0_3_43"
else
    TEMPLATE_DB="ptf_planner_banco_limpo_9_0_0_0_0"
fi

# Permitir override via variável de ambiente (se necessário)
TEMPLATE_DB="${TEMPLATE_DB_OVERRIDE:-$TEMPLATE_DB}"

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

log "🔗 Template: $TEMPLATE_HOST:$TEMPLATE_PORT ($TEMPLATE_SERVER_NAME) → destino: $EFFECTIVE_HOST:$EFFECTIVE_PORT"

# 1. Verificar ferramentas necessárias
if ! command -v psql &> /dev/null; then
    log_error "PostgreSQL client (psql) não encontrado no agente"
    exit 1
fi

# 2. Testar conexão com o banco antes de prosseguir
log "🔍 Testando conexão com o servidor de banco em $EFFECTIVE_HOST:$EFFECTIVE_PORT..."

# Usar template database para teste pois usuário pode não ter acesso ao 'postgres'
# Capturar erro específico usando função segura
PSQL_ERROR=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "SELECT 1;" 2>&1)
PSQL_EXIT_CODE=$?

if [ $PSQL_EXIT_CODE -ne 0 ]; then
    log_error "Falha ao conectar em $EFFECTIVE_HOST:$EFFECTIVE_PORT (usuário: $DB_USER) — $PSQL_ERROR"
    exit 1
fi
log_success "Conexão com o servidor estabelecida com sucesso!"

# 2. Verificar se template existe no servidor de template
log "🔍 Verificando se template existe no $TEMPLATE_SERVER_NAME: $TEMPLATE_DB"
# Conectar no próprio template para verificar se existe e se temos acesso
if ! run_psql_safe psql -h "$TEMPLATE_HOST" -p "$TEMPLATE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "SELECT 1;" &>/dev/null; then
    log_error "Template '$TEMPLATE_DB' não encontrado ou sem acesso em $TEMPLATE_HOST:$TEMPLATE_PORT ($TEMPLATE_SERVER_NAME, usuário: $DB_USER)"
    exit 1
fi
log_success "Template $TEMPLATE_DB encontrado no $TEMPLATE_SERVER_NAME!"

# 3. Criar banco de dados copiando template do GCP01
log "🗄️ Criando banco $NOME_BANCO no servidor de destino..."

# Primeiro verificar se o banco já existe no destino
# Conectar no template para fazer a verificação
if run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "\l" | grep -qw "$NOME_BANCO"; then
    if [[ "$ALLOW_EXISTING_DB" == "true" ]]; then
        log_warning "Banco $NOME_BANCO já existe no servidor de destino e ALLOW_EXISTING_DB=true; continuando sem recriar."
    else
        log_error "Banco $NOME_BANCO já existe no servidor de destino."
        log_error "Não é possível garantir a versão final desejada ($VERSAO_BANCO) sem recriar o banco."
        log_error "Use um novo nome de banco ou remova o banco existente antes de executar o pipeline."
        log_error "Se precisar manter o comportamento antigo, execute com ALLOW_EXISTING_DB=true."
        exit 1
    fi
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
    log_error "Nenhum arquivo de dados encontrado — esperado: $DADOS_FILE_TEMP ou $DADOS_FILE_DEFAULT"
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

# 5. Definir versão base inicial por ambiente (sem consulta ao banco)
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    VERSAO_ATUAL="15.12.0.3-43"
else
    VERSAO_ATUAL="9.0.0.0-0"
fi

# 6. Executar updates necessários
log "🔄 Executando updates necessários ($VERSAO_ATUAL → $VERSAO_BANCO)..."
UPDATES_DIR="${UPDATES_DIR_OVERRIDE:-$WORKSPACE/sql/$TIPO_AMBIENTE/updates}"
if [[ -d "$UPDATES_DIR" ]]; then
    UPDATE_COUNT=0
    mapfile -t sorted_updates < <(find "$UPDATES_DIR" -maxdepth 1 -type f -name "*.sql" | sort -V)

    eligible_update_files=()

    for update_file in "${sorted_updates[@]}"; do
        if [[ -f "$update_file" ]]; then
            update_label=$(basename "$update_file" .sql)
            if ! update_version=$(extract_version_token "$update_label"); then
                log_warning "Pulando arquivo sem versão reconhecida no nome: $update_label"
                continue
            fi
            
            # Verificar se update deve ser aplicado usando comparação numérica de versões
            # Condição: versão do update > versão atual E versão do update <= versão desejada
            comp_atual=$(compare_versions "$update_version" "$VERSAO_ATUAL")
            comp_desejada=$(compare_versions "$update_version" "$VERSAO_BANCO")
            
            # update_version > VERSAO_ATUAL AND update_version <= VERSAO_BANCO
            if [[ "$comp_atual" == "1" ]] && [[ "$comp_desejada" == "-1" || "$comp_desejada" == "0" ]]; then
                eligible_update_files+=("$update_file")
            else
                log "⏭️ Pulando update $update_version (fora do intervalo $VERSAO_ATUAL < x <= $VERSAO_BANCO)"
            fi
        fi
    done

    if [[ "${#eligible_update_files[@]}" -eq 0 ]]; then
        log_warning "Nenhum update encontrado dentro do intervalo: $VERSAO_ATUAL < x <= $VERSAO_BANCO"
    else
        log "📌 Versões dentro do intervalo ($VERSAO_ATUAL < x <= $VERSAO_BANCO):"
        for update_file in "${eligible_update_files[@]}"; do
            update_label=$(basename "$update_file" .sql)
            update_version=$(extract_version_token "$update_label" || echo "$update_label")
            log "   - $update_version ($update_label)"
        done
    fi

    for update_file in "${eligible_update_files[@]}"; do
        update_label=$(basename "$update_file" .sql)
        update_version=$(extract_version_token "$update_label" || echo "$update_label")
        log "🔄 Aplicando update: $update_label [versão: $update_version] (atual: $VERSAO_ATUAL, desejada: $VERSAO_BANCO)"
        if execute_sql_file "$update_file" "$NOME_BANCO"; then
            ((UPDATE_COUNT++))
            log_success "Update $update_version aplicado"
        else
            log_error "Falha ao aplicar update $update_version"
            exit 1
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

log_success "Banco '$NOME_BANCO' criado — versão: $VERSAO_BANCO ($UPDATE_COUNT updates aplicados)"

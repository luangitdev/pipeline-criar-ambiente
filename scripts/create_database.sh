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
DB_INTERNAL_HOST=""
DB_PORT="5432"
DB_USER=""
DB_PASSWORD=""
WORKSPACE=""
UPDATES_DIR_OVERRIDE=""
ALLOW_EXISTING_DB="${ALLOW_EXISTING_DB:-false}"
MULTIBANCO="false"
BANCOS_FILIAIS_FILE=""

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
        --db-internal-host)
            DB_INTERNAL_HOST="$2"
            shift 2
            ;;
        --multibanco)
            MULTIBANCO="$2"
            shift 2
            ;;
        --bancos-filiais-file)
            BANCOS_FILIAIS_FILE="$2"
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

# Aplica start.sql, config.sql, updates e credentials em um banco.
# Uso: configure_db <nome_banco> <versao_inicial>
configure_db() {
    local target_db="$1"
    local versao_inicial="$2"

    # Gerar start.sql personalizado
    "$WORKSPACE/scripts/generate_start_sql.sh" "$DADOS_FILE" "$TIPO_AMBIENTE" "$WORKSPACE/temp"

    local START_SQL="$WORKSPACE/temp/start_${TIPO_AMBIENTE}.sql"
    if [[ -f "$START_SQL" ]]; then
        log "🔧 Executando configuração inicial em '$target_db'..."
        if execute_sql_file "$START_SQL" "$target_db"; then
            log_success "Configuração inicial aplicada"
        else
            log_error "Falha ao aplicar configuração inicial"
            return 1
        fi
    else
        log_warning "Arquivo start.sql não encontrado: $START_SQL"
        log "🔍 Listando conteúdo de temp/:"
        ls -la "$WORKSPACE/temp/" || log_warning "Diretório temp não existe"
    fi

    local CONFIG_SQL="$WORKSPACE/sql/$TIPO_AMBIENTE/config.sql"
    if [[ -f "$CONFIG_SQL" && "$TIPO_AMBIENTE" != "pln" ]]; then
        log "⚙️ Executando scripts de configuração em '$target_db'..."
        if execute_sql_file "$CONFIG_SQL" "$target_db"; then
            log_success "Scripts de configuração aplicados"
        else
            log_error "Falha ao aplicar configuração"
            return 1
        fi
    fi

    log "🔄 Executando updates necessários em '$target_db' ($versao_inicial → $VERSAO_BANCO)..."
    local UPDATES_DIR="${UPDATES_DIR_OVERRIDE:-$WORKSPACE/sql/$TIPO_AMBIENTE/updates}"
    local UPDATE_COUNT=0
    if [[ -d "$UPDATES_DIR" ]]; then
        local sorted_updates=()
        mapfile -t sorted_updates < <(find "$UPDATES_DIR" -maxdepth 1 -type f -name "*.sql" | sort -V)
        local eligible_update_files=()

        for update_file in "${sorted_updates[@]}"; do
            if [[ -f "$update_file" ]]; then
                local update_label
                update_label=$(basename "$update_file" .sql)
                local update_version
                if ! update_version=$(extract_version_token "$update_label"); then
                    log_warning "Pulando arquivo sem versão reconhecida no nome: $update_label"
                    continue
                fi
                local comp_atual comp_desejada
                comp_atual=$(compare_versions "$update_version" "$versao_inicial")
                comp_desejada=$(compare_versions "$update_version" "$VERSAO_BANCO")
                if [[ "$comp_atual" == "1" ]] && [[ "$comp_desejada" == "-1" || "$comp_desejada" == "0" ]]; then
                    eligible_update_files+=("$update_file")
                fi
            fi
        done

        for update_file in "${eligible_update_files[@]}"; do
            local update_label
            update_label=$(basename "$update_file" .sql)
            local update_version
            update_version=$(extract_version_token "$update_label" || echo "$update_label")
            log "🔄 Aplicando update: $update_label [versão: $update_version]"
            if execute_sql_file "$update_file" "$target_db"; then
                ((UPDATE_COUNT++))
                log_success "Update $update_version aplicado"
            else
                log_error "Falha ao aplicar update $update_version"
                return 1
            fi
        done
        log_success "$UPDATE_COUNT updates aplicados em '$target_db'"
    else
        log_warning "Diretório de updates não encontrado: $UPDATES_DIR"
    fi

    local CREDENTIALS_SQL="$WORKSPACE/sql/$TIPO_AMBIENTE/credentials.sql"
    if [[ -f "$CREDENTIALS_SQL" ]]; then
        log "🔐 Aplicando credenciais em '$target_db'..."
        if execute_sql_file "$CREDENTIALS_SQL" "$target_db"; then
            log_success "Credenciais aplicadas com sucesso"
        else
            log_warning "Erro ao aplicar credenciais (pode ser normal se usuários já existem)"
        fi
    fi
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
    
    # Executar SQL com ON_ERROR_STOP para detectar falhas individuais de SQL
    if ! SQL_OUTPUT=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$database" -v ON_ERROR_STOP=1 -f "$file" 2>&1); then
        log_error "Falha ao executar $(basename "$file"):"
        echo "$SQL_OUTPUT"
        return 1
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

# Primeiro verificar se o banco já existe no destino via query SQL (evita truncamento de nomes longos no \l)
DB_EXISTS=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = '$NOME_BANCO';" 2>/dev/null || echo "")
if [[ "$DB_EXISTS" == "1" ]]; then
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
    CREATE_DB_OUTPUT=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -c "CREATE DATABASE \"$NOME_BANCO\";" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Falha ao criar banco vazio $NOME_BANCO no servidor de destino:"
        echo "$CREATE_DB_OUTPUT"
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

# Versão base inicial por ambiente (sem consulta ao banco)
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    VERSAO_BASE_INICIAL="15.12.0.3-43"
else
    VERSAO_BASE_INICIAL="9.0.0.0-0"
fi

# 3-7. Configurar base principal
configure_db "$NOME_BANCO" "$VERSAO_BASE_INICIAL"

# ==================== MULTIBANCO ====================
if [[ "$MULTIBANCO" == "true" ]]; then
    log "[MULTIBANCO] 🔀 Iniciando criação de bases filiais..."

    if [[ -z "$BANCOS_FILIAIS_FILE" || ! -f "$BANCOS_FILIAIS_FILE" ]]; then
        log_error "[MULTIBANCO] Arquivo de bancos filiais não encontrado: '${BANCOS_FILIAIS_FILE}'"
        exit 1
    fi

    # Extrair CNPJ e Razão Social da base principal (matriz) a partir do dados.txt
    MATRIZ_CNPJ=$(grep -i '^CNPJ:' "$DADOS_FILE" | head -1 | cut -d':' -f2- | tr -cd '0-9' || echo "")
    MATRIZ_RAZAO=$(grep -i '^Razao Social:' "$DADOS_FILE" | head -1 | sed 's/^[Rr]azao [Ss]ocial:[[:space:]]*//' | xargs || echo "")

    if [[ -z "$MATRIZ_CNPJ" ]]; then
        log_error "[MULTIBANCO] CNPJ da matriz não encontrado em '$DADOS_FILE'"
        exit 1
    fi
    log "[MULTIBANCO] Matriz → CNPJ=$MATRIZ_CNPJ | Nome=$MATRIZ_RAZAO"

    # IP efetivo para db_url (usar IP interno se disponível)
    JDBC_HOST="${DB_INTERNAL_HOST:-$DB_HOST}"

    # Criar banco filial + registro multi_db_connection
    create_filial() {
        local filial_nome="$1"
        local filial_cnpj="$2"
        local filial_empresa="$3"

        log "[MULTIBANCO] ── Criando filial '$filial_nome' (CNPJ=$filial_cnpj)..."

        # Verificar existência
        local DB_EXISTS
        DB_EXISTS=$(run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" -tAc \
            "SELECT 1 FROM pg_database WHERE datname = '$filial_nome';" 2>/dev/null || echo "")

        if [[ "$DB_EXISTS" == "1" ]]; then
            if [[ "$ALLOW_EXISTING_DB" == "true" ]]; then
                log_warning "[MULTIBANCO] Banco '$filial_nome' já existe; continuando sem recriar (ALLOW_EXISTING_DB=true)."
            else
                log_error "[MULTIBANCO] Banco '$filial_nome' já existe. Use ALLOW_EXISTING_DB=true para ignorar."
                return 1
            fi
        else
            # Criar banco vazio
            run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" \
                -c "CREATE DATABASE \"$filial_nome\";" || { log_error "[MULTIBANCO] Falha ao criar banco '$filial_nome'"; return 1; }

            # pg_dump/pg_restore do template
            local DUMP_FILE="/tmp/template_dump_filial_$$.sql"
            log "[MULTIBANCO] 📤 Dump do template para '$filial_nome'..."
            if ! run_psql_safe pg_dump -h "$TEMPLATE_HOST" -p "$TEMPLATE_PORT" -U "$DB_USER" -d "$TEMPLATE_DB" > "$DUMP_FILE"; then
                log_error "[MULTIBANCO] Falha no dump do template"
                rm -f "$DUMP_FILE"
                return 1
            fi
            log "[MULTIBANCO] 📥 Restore em '$filial_nome'..."
            if ! run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$filial_nome" < "$DUMP_FILE"; then
                log_error "[MULTIBANCO] Falha no restore em '$filial_nome'"
                rm -f "$DUMP_FILE"
                return 1
            fi
            rm -f "$DUMP_FILE"
            log_success "[MULTIBANCO] Banco '$filial_nome' criado com dados do template."
        fi

        # Configurar (start.sql, config.sql, updates, credentials)
        configure_db "$filial_nome" "$VERSAO_BASE_INICIAL"
        log_success "[MULTIBANCO] Filial '$filial_nome' configurada."
    }

    # Iterar sobre filiais
    while IFS= read -r linha || [[ -n "$linha" ]]; do
        linha="${linha//[$'\r']}"
        [[ -z "${linha// }" ]] && continue
        IFS=':' read -r f_nome f_cnpj f_empresa <<< "$linha"
        # Capturar resto após segundo : como nome da empresa (suporte a : no nome)
        f_nome="${f_nome// }"
        f_cnpj="${f_cnpj// }"
        # f_empresa pode conter os : restantes — já capturado corretamente pelo read com 3 vars
        f_empresa=$(echo "$linha" | cut -d':' -f3-)
        create_filial "$f_nome" "$f_cnpj" "$f_empresa"
    done < "$BANCOS_FILIAIS_FILE"

    # Registrar todas as bases (principal + filiais) na multi_db_connection da base principal
    log "[MULTIBANCO] 📝 Registrando conexões na multi_db_connection de '$NOME_BANCO'..."

    insert_multi_db() {
        local db_name="$1"
        local empresa_cnpj="$2"
        local empresa_nome="$3"
        local db_url="${JDBC_HOST}:${DB_PORT}/${db_name}"

        # Escapar aspas simples no nome da empresa para segurança SQL
        local empresa_nome_escaped="${empresa_nome//\'/\'\'}"

        local sql="INSERT INTO multi_db_connection (db_url, db_user, db_password, empresa_cnpj, empresa_nome)
VALUES ('${db_url}', '${DB_USER}', '$(echo "$DB_PASSWORD_ENCODED" | base64 -d | sed "s/'/\\''/g")', '${empresa_cnpj}', '${empresa_nome_escaped}')
ON CONFLICT DO NOTHING;"

        if ! run_psql_safe psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$DB_USER" -d "$NOME_BANCO" -c "$sql"; then
            log_warning "[MULTIBANCO] Falha ao inserir '$db_name' na multi_db_connection. Verifique manualmente."
        else
            log_success "[MULTIBANCO] Conexão '$db_name' registrada na multi_db_connection."
        fi
    }

    # Inserir matriz
    insert_multi_db "$NOME_BANCO" "$MATRIZ_CNPJ" "$MATRIZ_RAZAO"

    # Inserir filiais
    while IFS= read -r linha || [[ -n "$linha" ]]; do
        linha="${linha//[$'\r']}"
        [[ -z "${linha// }" ]] && continue
        f_nome=$(echo "$linha" | cut -d':' -f1)
        f_cnpj=$(echo "$linha" | cut -d':' -f2)
        f_empresa=$(echo "$linha" | cut -d':' -f3-)
        insert_multi_db "$f_nome" "$f_cnpj" "$f_empresa"
    done < "$BANCOS_FILIAIS_FILE"

    log_success "[MULTIBANCO] Todas as conexões registradas em '$NOME_BANCO'."
fi
# ====================================================

# Conexão finalizada

log_success "Banco '$NOME_BANCO' criado — versão: $VERSAO_BANCO"

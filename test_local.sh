#!/bin/bash

# Script de teste local para o pipeline
# Simula a execução do Jenkins localmente

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 TESTE LOCAL DO PIPELINE${NC}"
echo "=============================="

# Configuração do teste
PIPELINE_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WORKSPACE="$PIPELINE_HOME"
export SCRIPTS_PATH="$PIPELINE_HOME/scripts"
export CONFIG_PATH="$PIPELINE_HOME/config"
export SQL_PATH="$PIPELINE_HOME/sql"
export DADOS_PATH="$PIPELINE_HOME/dados"

# Parâmetros de teste
TIPO_AMBIENTE="ptf"
SERVIDOR="local01"
NOME_BANCO="teste_pipeline_$(date +%s)"
VERSAO_DESEJADA="15.13.1.0-1"
CRIAR_BANCO="true"
DEPLOY_APP="false"

# Credenciais de teste (substitua pelas suas)
DB_USER="pathfinddb"
DB_PASSWORD="Find**(path)\$DB"

echo -e "${YELLOW}📋 Parâmetros de teste:${NC}"
echo "   - Ambiente: $TIPO_AMBIENTE"
echo "   - Servidor: $SERVIDOR" 
echo "   - Banco: $NOME_BANCO"
echo "   - Versão: $VERSAO_DESEJADA"
echo ""

# Função de log
log_step() {
    echo -e "${BLUE}🔄 $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

# Teste 1: Validação de parâmetros
log_step "Teste 1: Validação de parâmetros"
if [[ -n "$NOME_BANCO" && -n "$VERSAO_DESEJADA" ]]; then
    log_success "Parâmetros válidos"
else
    log_error "Parâmetros inválidos"
    exit 1
fi

# Teste 2: Verificar scripts
log_step "Teste 2: Verificando scripts"
SCRIPTS_REQUIRED=(
    "get_db_host.sh"
    "create_database.sh" 
    "generate_start_sql.sh"
    "verify_database.sh"
)

for script in "${SCRIPTS_REQUIRED[@]}"; do
    if [[ -x "$SCRIPTS_PATH/$script" ]]; then
        log_success "Script $script encontrado e executável"
    else
        log_error "Script $script não encontrado ou sem permissão"
        exit 1
    fi
done

# Teste 3: Verificar estrutura de dados
log_step "Teste 3: Verificando dados do ambiente"
DADOS_FILE="$DADOS_PATH/$TIPO_AMBIENTE/dados.txt"
if [[ -f "$DADOS_FILE" ]]; then
    log_success "Arquivo de dados encontrado: $DADOS_FILE"
    echo "   Conteúdo:"
    head -3 "$DADOS_FILE" | sed 's/^/   /'
else
    log_error "Arquivo de dados não encontrado: $DADOS_FILE"
fi

# Teste 4: Verificar SQL
log_step "Teste 4: Verificando arquivos SQL"
SQL_FILES=(
    "$SQL_PATH/$TIPO_AMBIENTE/config.sql"
    "$SQL_PATH/$TIPO_AMBIENTE/credentials.sql"
)

for sql_file in "${SQL_FILES[@]}"; do
    if [[ -f "$sql_file" ]]; then
        log_success "Arquivo SQL encontrado: $(basename $sql_file)"
    else
        log_error "Arquivo SQL não encontrado: $sql_file"
    fi
done

# Contar updates
UPDATES_COUNT=$(find "$SQL_PATH/$TIPO_AMBIENTE/updates" -name "*.sql" 2>/dev/null | wc -l || echo "0")
log_success "Updates disponíveis: $UPDATES_COUNT"

# Teste 5: Testar mapeamento de servidor
log_step "Teste 5: Testando mapeamento de servidor"
if DB_HOST=$("$SCRIPTS_PATH/get_db_host.sh" "$SERVIDOR"); then
    log_success "Host mapeado: $SERVIDOR -> $DB_HOST"
else
    log_error "Falha no mapeamento do servidor"
    exit 1
fi

# Teste 6: Gerar SQL personalizado (simulação)
log_step "Teste 6: Testando geração de SQL personalizado"
mkdir -p "$WORKSPACE/temp"
if "$SCRIPTS_PATH/generate_start_sql.sh" "$DADOS_FILE" "$TIPO_AMBIENTE" "$WORKSPACE/temp" 2>/dev/null; then
    if [[ -f "$WORKSPACE/temp/start_${TIPO_AMBIENTE}.sql" ]]; then
        log_success "SQL personalizado gerado com sucesso"
        SIZE=$(wc -l < "$WORKSPACE/temp/start_${TIPO_AMBIENTE}.sql")
        echo "   Linhas geradas: $SIZE"
    else
        log_error "Arquivo SQL não foi criado"
    fi
else
    log_error "Falha na geração do SQL personalizado"
fi

# Teste 7: Verificar dependências do sistema
log_step "Teste 7: Verificando dependências do sistema"
DEPS=(psql jar)
for dep in "${DEPS[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        log_success "Dependência encontrada: $dep"
    else
        echo -e "${YELLOW}⚠️ Dependência não encontrada: $dep${NC}"
    fi
done

# Limpeza
rm -rf "$WORKSPACE/temp"

echo ""
echo -e "${GREEN}🎉 TESTE LOCAL CONCLUÍDO COM SUCESSO!${NC}"
echo "======================================"
echo ""
echo -e "${BLUE}📝 Próximos passos:${NC}"
echo "1. Configure as credenciais no Jenkins:"
echo "   - db-pathfind-user"
echo "   - db-pathfind-password"
echo ""
echo "2. Importe o Jenkinsfile no Jenkins"
echo ""
echo "3. Execute o pipeline com os parâmetros desejados"
echo ""
echo -e "${YELLOW}💡 Dica:${NC} Para testar com banco real, configure as credenciais e execute:"
echo "   CRIAR_BANCO=true ./test_local.sh"
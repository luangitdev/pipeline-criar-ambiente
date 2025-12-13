#!/bin/bash

# Script para verificar se o deployment foi realizado corretamente

set -euo pipefail

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# Parse argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy-path)
            DEPLOY_PATH="$2"
            shift 2
            ;;
        --nome-banco)
            NOME_BANCO="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

APP_DIR="$DEPLOY_PATH/$NOME_BANCO"

log "🔍 Verificando deployment em: $APP_DIR"

# Verificar se diretório existe
if [[ ! -d "$APP_DIR" ]]; then
    log_error "Diretório da aplicação não encontrado: $APP_DIR"
    exit 1
fi

log_success "Diretório da aplicação existe"

# Verificar estrutura de diretórios
log "📁 Verificando estrutura..."
DIRETORIOS=("webapp" "logs")
for dir in "${DIRETORIOS[@]}"; do
    if [[ -d "$APP_DIR/$dir" ]]; then
        log_success "Diretório $dir existe"
    else
        log_error "Diretório $dir não encontrado!"
        exit 1
    fi
done

# Verificar arquivos essenciais
log "📄 Verificando arquivos..."
ARQUIVOS=(
    "webapp/WEB-INF/classes/application.properties"
    "start.sh"
    "stop.sh"
)

for arquivo in "${ARQUIVOS[@]}"; do
    if [[ -f "$APP_DIR/$arquivo" ]]; then
        log_success "Arquivo $arquivo existe"
    else
        log_error "Arquivo $arquivo não encontrado!"
        exit 1
    fi
done

# Verificar permissões dos scripts
log "⚙️ Verificando permissões..."
SCRIPTS=("start.sh" "stop.sh")
for script in "${SCRIPTS[@]}"; do
    if [[ -x "$APP_DIR/$script" ]]; then
        log_success "Script $script é executável"
    else
        log_warning "Script $script não é executável, corrigindo..."
        chmod +x "$APP_DIR/$script"
        log_success "Permissão corrigida para $script"
    fi
done

# Verificar conteúdo da webapp
log "🔍 Verificando conteúdo da webapp..."
WEBAPP_DIR="$APP_DIR/webapp"

if [[ -d "$WEBAPP_DIR/WEB-INF" ]]; then
    log_success "Estrutura WEB-INF existe"
else
    log_error "Estrutura WEB-INF não encontrada!"
    exit 1
fi

# Contar arquivos na webapp
FILE_COUNT=$(find "$WEBAPP_DIR" -type f | wc -l)
log "📋 Total de arquivos na webapp: $FILE_COUNT"

if [[ $FILE_COUNT -lt 10 ]]; then
    log_warning "Poucos arquivos encontrados, verifique se o WAR foi extraído corretamente"
else
    log_success "Quantidade adequada de arquivos encontrada"
fi

# Verificar tamanho do diretório
SIZE=$(du -sh "$APP_DIR" | cut -f1)
log "📎 Tamanho total da aplicação: $SIZE"

# Verificar configuração
APP_PROPS="$APP_DIR/webapp/WEB-INF/classes/application.properties"
if [[ -f "$APP_PROPS" ]]; then
    log "⚙️ Verificando configurações..."
    
    if grep -q "$NOME_BANCO" "$APP_PROPS"; then
        log_success "Nome do banco configurado corretamente"
    else
        log_warning "Nome do banco pode não estar configurado"
    fi
    
    if grep -q "spring.datasource.url" "$APP_PROPS"; then
        log_success "URL do banco configurada"
    else
        log_warning "URL do banco não encontrada"
    fi
fi

log_success "✅ Verificação do deployment concluída com sucesso!"
log "📂 Resumo da aplicação:"
log "   - Diretório: $APP_DIR"
log "   - Tamanho: $SIZE"
log "   - Arquivos: $FILE_COUNT"
log ""
log "🚀 Para iniciar: $APP_DIR/start.sh"
log "🛑 Para parar: $APP_DIR/stop.sh"
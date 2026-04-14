#!/bin/bash

# Script para operações de banco via bastion host
# Assume que o bastion já tem acesso direto aos bancos

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log_utils.sh"

DB_HOST=""
DB_PORT="5432"
DB_USER=""
DB_PASSWORD=""
DB_NAME=""
OPERATION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --operation)
            OPERATION="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

# Set PGPASSWORD for non-interactive operations
export PGPASSWORD="$DB_PASSWORD"

case $OPERATION in
    "create")
        log "🗄️ Criando banco '$DB_NAME' em $DB_HOST:$DB_PORT..."
        createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
        log_success "Banco '$DB_NAME' criado"
        ;;
    
    "backup")
        log "💾 Executando backup de '$DB_NAME'..."
        pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "/tmp/${DB_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql"
        log_success "Backup de '$DB_NAME' concluído"
        ;;
    
    "restore")
        BACKUP_FILE="$5"  # Arquivo de backup
        log "🔄 Restaurando '$DB_NAME' de: $BACKUP_FILE"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "$BACKUP_FILE"
        log_success "Restore de '$DB_NAME' concluído"
        ;;
    
    "execute_sql")
        SQL_FILE="$5"  # Arquivo SQL para executar
        log "📝 Executando SQL: $SQL_FILE"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE"
        log_success "SQL executado: $SQL_FILE"
        ;;
    
    "test_connection")
        log "🔍 Testando conexão em $DB_HOST:$DB_PORT (banco: $DB_NAME)..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();"
        log_success "Conexão OK — $DB_HOST:$DB_PORT"
        ;;
    
    *)
        log_error "Operação desconhecida: $OPERATION (disponíveis: create, backup, restore, execute_sql, test_connection)"
        exit 1
        ;;
esac

# Clear password from environment
unset PGPASSWORD
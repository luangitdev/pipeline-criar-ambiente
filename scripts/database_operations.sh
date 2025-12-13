#!/bin/bash

# Script para operações de banco via bastion host
# Assume que o bastion já tem acesso direto aos bancos

set -e

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
            echo "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

# Set PGPASSWORD for non-interactive operations
export PGPASSWORD="$DB_PASSWORD"

case $OPERATION in
    "create")
        echo "🗄️ Criando banco de dados: $DB_NAME"
        createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
        echo "✅ Banco $DB_NAME criado com sucesso!"
        ;;
    
    "backup")
        echo "💾 Executando backup do banco: $DB_NAME"
        pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "/tmp/${DB_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql"
        echo "✅ Backup concluído!"
        ;;
    
    "restore")
        BACKUP_FILE="$5"  # Arquivo de backup
        echo "🔄 Restaurando banco $DB_NAME do arquivo: $BACKUP_FILE"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "$BACKUP_FILE"
        echo "✅ Restore concluído!"
        ;;
    
    "execute_sql")
        SQL_FILE="$5"  # Arquivo SQL para executar
        echo "📝 Executando SQL: $SQL_FILE"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE"
        echo "✅ SQL executado com sucesso!"
        ;;
    
    "test_connection")
        echo "🔍 Testando conexão com o banco..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();"
        echo "✅ Conexão OK!"
        ;;
    
    *)
        echo "❌ Operação desconhecida: $OPERATION"
        echo "Operações disponíveis: create, backup, restore, execute_sql, test_connection"
        exit 1
        ;;
esac

# Clear password from environment
unset PGPASSWORD
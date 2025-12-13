#!/bin/bash

# Script para deploy de aplicação WAR
# Descompacta o WAR e configura a aplicação

set -euo pipefail

# Cores para output
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

# Variáveis
WAR_FILE=""
DEPLOY_PATH=""
NOME_BANCO=""
TIPO_AMBIENTE=""
SERVIDOR=""
WORKSPACE=""

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --war-file)
            WAR_FILE="$2"
            shift 2
            ;;
        --deploy-path)
            DEPLOY_PATH="$2"
            shift 2
            ;;
        --nome-banco)
            NOME_BANCO="$2"
            shift 2
            ;;
        --tipo-ambiente)
            TIPO_AMBIENTE="$2"
            shift 2
            ;;
        --servidor)
            SERVIDOR="$2"
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
if [[ -z "$WAR_FILE" || -z "$DEPLOY_PATH" || -z "$NOME_BANCO" ]]; then
    log_error "Parâmetros obrigatórios faltando!"
    exit 1
fi

if [[ ! -f "$WAR_FILE" ]]; then
    log_error "Arquivo WAR não encontrado: $WAR_FILE"
    exit 1
fi

log "🚀 INICIANDO DEPLOY DA APLICAÇÃO"
log "📋 Configuração:"
log "   - WAR: $WAR_FILE"
log "   - Deploy Path: $DEPLOY_PATH"
log "   - Banco: $NOME_BANCO"
log "   - Ambiente: $TIPO_AMBIENTE"
log "   - Servidor: $SERVIDOR"

# Criar estrutura de diretórios
APP_DIR="$DEPLOY_PATH/$NOME_BANCO"
log "📁 Criando diretório da aplicação: $APP_DIR"
mkdir -p "$APP_DIR"

# Backup se já existe aplicação
if [[ -d "$APP_DIR/webapp" ]]; then
    BACKUP_DIR="$APP_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    log "📦 Fazendo backup para: $BACKUP_DIR"
    mv "$APP_DIR/webapp" "$BACKUP_DIR"
fi

# Criar diretório webapp
mkdir -p "$APP_DIR/webapp"

# Extrair WAR
log "📤 Extraindo arquivo WAR..."
cd "$APP_DIR/webapp"
jar -xf "$WAR_FILE"
log_success "WAR extraído com sucesso"

# Gerar configurações da aplicação
log "⚙️ Gerando configurações da aplicação..."

# Criar application.properties personalizado
APP_PROPS="$APP_DIR/webapp/WEB-INF/classes/application.properties"
mkdir -p "$(dirname "$APP_PROPS")"

# Obter configurações do banco
DB_HOST=$("$WORKSPACE/scripts/get_db_host.sh" "$SERVIDOR")

cat > "$APP_PROPS" << EOF
# Configurações geradas automaticamente
# Data: $(date)
# Ambiente: $TIPO_AMBIENTE
# Servidor: $SERVIDOR
# Banco: $NOME_BANCO

# Configurações do banco de dados
spring.datasource.url=jdbc:postgresql://$DB_HOST:5432/$NOME_BANCO
spring.datasource.username=\${DB_USER:pathfinddb}
spring.datasource.password=\${DB_PASSWORD:Find**(path)\$DB}
spring.datasource.driver-class-name=org.postgresql.Driver

# Configurações JPA
spring.jpa.hibernate.ddl-auto=none
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# Configurações do ambiente
app.ambiente=$TIPO_AMBIENTE
app.servidor=$SERVIDOR
app.nome.banco=$NOME_BANCO

# Configurações de logging
logging.level.com.pathfind=INFO
logging.file.path=$APP_DIR/logs
logging.file.name=application.log

# Configurações do servidor
server.port=8080
server.servlet.context-path=/$NOME_BANCO

EOF

log_success "application.properties criado"

# Criar script de inicialização
START_SCRIPT="$APP_DIR/start.sh"
cat > "$START_SCRIPT" << EOF
#!/bin/bash

# Script de inicialização da aplicação $NOME_BANCO
# Gerado automaticamente em $(date)

set -euo pipefail

APP_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
WEBAPP_DIR="\$APP_DIR/webapp"
LOGS_DIR="\$APP_DIR/logs"

# Criar diretório de logs
mkdir -p "\$LOGS_DIR"

# Configurações Java
JAVA_OPTS="-Xms512m -Xmx2g -Dfile.encoding=UTF-8"

# Variáveis de ambiente
export DB_USER="pathfinddb"
export DB_PASSWORD="Find**(path)\$DB"

# Executar aplicação
echo "🚀 Iniciando aplicação $NOME_BANCO..."
echo "📍 Diretório: \$WEBAPP_DIR"
echo "📝 Logs: \$LOGS_DIR/application.log"

cd "\$WEBAPP_DIR"
java \$JAVA_OPTS -jar "\$WEBAPP_DIR/WEB-INF/lib/*.jar" > "\$LOGS_DIR/application.log" 2>&1 &

echo "✅ Aplicação iniciada com PID: \$!"
echo "\$!" > "\$APP_DIR/app.pid"

EOF

chmod +x "$START_SCRIPT"
log_success "Script de inicialização criado: $START_SCRIPT"

# Criar script de parada
STOP_SCRIPT="$APP_DIR/stop.sh"
cat > "$STOP_SCRIPT" << EOF
#!/bin/bash

# Script de parada da aplicação $NOME_BANCO

set -euo pipefail

APP_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="\$APP_DIR/app.pid"

if [[ -f "\$PID_FILE" ]]; then
    PID=\$(cat "\$PID_FILE")
    if kill -0 "\$PID" 2>/dev/null; then
        echo "🛑 Parando aplicação $NOME_BANCO (PID: \$PID)..."
        kill "\$PID"
        sleep 5
        
        # Força parada se necessário
        if kill -0 "\$PID" 2>/dev/null; then
            echo "⚠️ Forçando parada..."
            kill -9 "\$PID"
        fi
        
        rm -f "\$PID_FILE"
        echo "✅ Aplicação parada com sucesso"
    else
        echo "⚠️ Processo não está rodando"
        rm -f "\$PID_FILE"
    fi
else
    echo "⚠️ Arquivo PID não encontrado"
fi

EOF

chmod +x "$STOP_SCRIPT"
log_success "Script de parada criado: $STOP_SCRIPT"

# Criar diretório de logs
mkdir -p "$APP_DIR/logs"

# Definir permissões
chown -R $(whoami):$(whoami) "$APP_DIR"

log_success "🎉 Deploy da aplicação concluído com sucesso!"
log "📂 Estrutura criada:"
log "   - App Dir: $APP_DIR"
log "   - WebApp: $APP_DIR/webapp"
log "   - Logs: $APP_DIR/logs"
log "   - Start: $START_SCRIPT"
log "   - Stop: $STOP_SCRIPT"
log ""
log "🚀 Para iniciar a aplicação:"
log "   $START_SCRIPT"
log ""
log "🛑 Para parar a aplicação:"
log "   $STOP_SCRIPT"
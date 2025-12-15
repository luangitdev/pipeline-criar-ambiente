#!/bin/bash

# Script para gerar start.sql personalizado baseado nos dados do ambiente
# Uso: generate_start_sql.sh <dados_file> <tipo_ambiente> <output_dir>

set -euo pipefail

DADOS_FILE="$1"
TIPO_AMBIENTE="$2"
OUTPUT_DIR="$3"

# Cores para output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log "🔄 Gerando start.sql personalizado..."

# Criar diretório de saída se não existir
mkdir -p "$OUTPUT_DIR"

# Inicializar variáveis com valores padrão
ENDERECO="N/A"
BAIRRO="N/A"
CIDADE="N/A"
ESTADO="N/A"
CEP="N/A"
LAT="0.0"
LONG="0.0"
CNPJ="N/A"
RAZAO_SOCIAL="N/A"
ESTADO_NOME="N/A"

# Processar arquivo de dados se existir
if [[ -f "$DADOS_FILE" ]]; then
    log "📄 Processando dados de: $DADOS_FILE"
    
    while IFS=':' read -r key value; do
        # Remover espaços e converter para minúsculo
        key=$(echo "$key" | xargs | tr '[:upper:]' '[:lower:]' | sed 's/ã/a/g; s/ç/c/g; s/ /_/g')
        
        case "$key" in
            "endereco") ENDERECO="$value" ;;
            "bairro") BAIRRO="$value" ;;
            "cidade") CIDADE="$value" ;;
            "estado") 
                ESTADO="$value"
                ESTADO_NOME="$value"
                ;;
            "cep") CEP="$value" ;;
            "lat"|"latitude") LAT="$value" ;;
            "long"|"longitude") LONG="$value" ;;
            "cnpj") CNPJ="$value" ;;
            "razao_social"|"razao social"|"razao_social") RAZAO_SOCIAL="$value" ;;
        esac
    done < "$DADOS_FILE"
    
    log_success "Dados processados com sucesso"
else
    log "⚠️ Arquivo de dados não encontrado, usando valores padrão"
fi

# Gerar SQL baseado no template
OUTPUT_FILE="$OUTPUT_DIR/start_${TIPO_AMBIENTE}.sql"

log "📝 Gerando arquivo: $OUTPUT_FILE"

# Template SQL personalizado
cat > "$OUTPUT_FILE" << EOF
-- Arquivo start.sql gerado automaticamente
-- Ambiente: $TIPO_AMBIENTE
-- Data: $(date)

-- Configurações iniciais do ambiente
BEGIN;

-- Garantir que as colunas necessárias existam na tabela empresa
DO \$\$ 
BEGIN
    -- Adicionar colunas se não existirem
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='endereco') THEN
        ALTER TABLE empresa ADD COLUMN endereco VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='bairro') THEN
        ALTER TABLE empresa ADD COLUMN bairro VARCHAR(100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='cidade') THEN
        ALTER TABLE empresa ADD COLUMN cidade VARCHAR(100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='estado') THEN
        ALTER TABLE empresa ADD COLUMN estado VARCHAR(2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='cep') THEN
        ALTER TABLE empresa ADD COLUMN cep VARCHAR(10);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='lat') THEN
        ALTER TABLE empresa ADD COLUMN lat DECIMAL(10,8);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='long') THEN
        ALTER TABLE empresa ADD COLUMN long DECIMAL(11,8);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='cnpj') THEN
        ALTER TABLE empresa ADD COLUMN cnpj VARCHAR(20);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='razao_social') THEN
        ALTER TABLE empresa ADD COLUMN razao_social VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='empresa' AND column_name='estado_nome') THEN
        ALTER TABLE empresa ADD COLUMN estado_nome VARCHAR(100);
    END IF;
END \$\$;

-- Inserir/atualizar dados da empresa
INSERT INTO empresa (endereco, bairro, cidade, estado, cep, lat, long, cnpj, razao_social, estado_nome)
VALUES (
    '$ENDERECO',
    '$BAIRRO', 
    '$CIDADE',
    '$ESTADO',
    '$CEP',
    $LAT,
    $LONG,
    '$CNPJ',
    '$RAZAO_SOCIAL',
    '$ESTADO_NOME'
)
ON CONFLICT (id) DO UPDATE SET
    endereco = EXCLUDED.endereco,
    bairro = EXCLUDED.bairro,
    cidade = EXCLUDED.cidade,
    estado = EXCLUDED.estado,
    cep = EXCLUDED.cep,
    lat = EXCLUDED.lat,
    long = EXCLUDED.long,
    cnpj = EXCLUDED.cnpj,
    razao_social = EXCLUDED.razao_social,
    estado_nome = EXCLUDED.estado_nome;

-- Configurações específicas por ambiente
EOF

# Adicionar configurações específicas do ambiente
if [[ "$TIPO_AMBIENTE" == "ptf" ]]; then
    cat >> "$OUTPUT_FILE" << EOF

-- Configurações específicas PTF
UPDATE configuracao SET valor_texto = 'PRODUCAO' WHERE nomecampo = 'ambiente';
UPDATE configuracao SET valor_texto = '$ENDERECO' WHERE nomecampo = 'endereco_empresa';
UPDATE configuracao SET valor_texto = '$RAZAO_SOCIAL' WHERE nomecampo = 'razao_social';

EOF
else
    cat >> "$OUTPUT_FILE" << EOF

-- Configurações específicas PLN
INSERT INTO configuracao_sistema (chave, valor) 
VALUES ('ambiente', 'PLANNER')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

EOF
fi

# Finalizar transação
cat >> "$OUTPUT_FILE" << EOF

COMMIT;

-- Fim do arquivo start.sql
EOF

log_success "Arquivo start.sql gerado: $OUTPUT_FILE"
log "📊 Dados utilizados:"
log "   - Endereço: $ENDERECO"
log "   - Cidade: $CIDADE"
log "   - Estado: $ESTADO"
log "   - CNPJ: $CNPJ"
log "   - Razão Social: $RAZAO_SOCIAL"
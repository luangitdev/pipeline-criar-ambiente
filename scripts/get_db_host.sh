#!/bin/bash

# Script para obter o host do banco de dados baseado no servidor
# Uso: get_db_host.sh <servidor>

set -euo pipefail

SERVIDOR="$1"

# Mapeamento de servidores para hosts de banco
case "$SERVIDOR" in
    "gcp01")
        echo "10.128.0.100"
        ;;
    "gcp02")
        echo "10.128.0.101"
        ;;
    "local01")
        echo "localhost"
        ;;
    *)
        echo "❌ Servidor desconhecido: $SERVIDOR" >&2
        exit 1
        ;;
esac
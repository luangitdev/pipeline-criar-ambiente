#!/bin/bash

# Script para obter o host do banco de dados baseado no servidor
# Uso: get_db_host.sh <servidor>

set -euo pipefail

SERVIDOR="$1"

# Mapeamento de servidores para hosts de banco
case "$SERVIDOR" in
    "gcp01")
        echo "10.200.0.19"
        ;;
    "gcp02")
        echo "10.200.0.29"
        ;;
    "gcp-pln")
        echo "10.200.0.3"
        ;;
    "gcp03")
        echo "10.200.0.40"
        ;;
    *)
        echo "❌ Servidor desconhecido: $SERVIDOR" >&2
        exit 1
        ;;
esac
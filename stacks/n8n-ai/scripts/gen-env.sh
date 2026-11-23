#!/bin/bash
#=============================================================================
# InfraStack — stack n8n-ai
# Genera .env a partir de .env.example reemplazando cada __GENERATE__ por un
# secreto aleatorio. No pisa un .env existente.
#
# Uso: scripts/gen-env.sh [--host n8n.midominio.com]
#=============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$STACK_DIR/.env.example"
TARGET="$STACK_DIR/.env"
HOST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; exit 1 ;;
    esac
done

if [[ -f "$TARGET" ]]; then
    echo "Ya existe $TARGET — no lo piso. Borralo a mano si querés regenerarlo." >&2
    exit 1
fi

command -v openssl >/dev/null || { echo "Falta openssl" >&2; exit 1; }

umask 077
while IFS= read -r line; do
    while [[ "$line" == *__GENERATE__* ]]; do
        line="${line/__GENERATE__/$(openssl rand -hex 32)}"
    done
    echo "$line"
done < "$EXAMPLE" > "$TARGET"

if [[ -n "$HOST" ]]; then
    sed -i \
        -e "s|^N8N_HOST=.*|N8N_HOST=${HOST}|" \
        -e "s|^N8N_PUBLIC_URL=.*|N8N_PUBLIC_URL=https://${HOST}/|" \
        "$TARGET"
fi

echo "Listo: $TARGET (permisos 600)"
echo "Guardá N8N_ENCRYPTION_KEY en Vaultwarden: grep ^N8N_ENCRYPTION_KEY= $TARGET"

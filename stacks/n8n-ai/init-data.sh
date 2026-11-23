#!/bin/bash
# Crea el usuario no-root que usa n8n. Corre solo la primera vez que se
# inicializa el volumen de Postgres (docker-entrypoint-initdb.d).
set -euo pipefail

if [[ -n "${POSTGRES_NON_ROOT_USER:-}" && -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
else
    echo "init-data.sh: faltan POSTGRES_NON_ROOT_USER / POSTGRES_NON_ROOT_PASSWORD" >&2
    exit 1
fi

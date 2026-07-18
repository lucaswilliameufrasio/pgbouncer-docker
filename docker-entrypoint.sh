#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Entrypoint do PgBouncer. Gera /etc/pgbouncer/pgbouncer.ini e
# /etc/pgbouncer/userlist.txt a partir de variáveis de ambiente, seguindo a
# mesma filosofia da imagem descontinuada da Bitnami: nada de editar arquivos
# a mão, tudo configurável via ENV. Veja o README.md para a lista completa
# de variáveis suportadas.
# ---------------------------------------------------------------------------
set -euo pipefail

# Ensure generated files are only readable by the owner
umask 077

CONFIG_DIR="/etc/pgbouncer"
INI_FILE="${CONFIG_DIR}/pgbouncer.ini"
USERLIST_FILE="${CONFIG_DIR}/userlist.txt"

log() { echo "[docker-entrypoint] $*" >&2; }

# Escape hatch: se o usuário já montou um pgbouncer.ini pronto, pula
# a geração automática.
if [ "${PGBOUNCER_SKIP_CONFIG_GENERATION:-false}" = "true" ]; then
    log "PGBOUNCER_SKIP_CONFIG_GENERATION=true, usando configuração existente em ${CONFIG_DIR}"
    exec "$@"
fi

# -----------------------------------------------------------------------
# 1. Resolve a conexão com o Postgres de origem.
#    Prioridade: DATABASE_URL > POSTGRESQL_* individuais.
# -----------------------------------------------------------------------
parse_database_url() {
    # postgres://user:pass@host:port/dbname?sslmode=require
    local url="$1"
    url="${url#postgres://}"
    url="${url#postgresql://}"

    local userinfo="${url%%@*}"
    local rest="${url#*@}"

    DB_USER="${userinfo%%:*}"
    DB_PASSWORD="${userinfo#*:}"
    [ "$DB_PASSWORD" = "$userinfo" ] && DB_PASSWORD=""

    local hostport="${rest%%/*}"
    local pathpart="${rest#*/}"

    DB_HOST="${hostport%%:*}"
    DB_PORT="${hostport#*:}"
    [ "$DB_PORT" = "$hostport" ] && DB_PORT="5432"

    DB_NAME="${pathpart%%\?*}"

    # decodifica %XX simples (percent-encoding) sem depender de python/perl
    DB_USER=$(printf '%b' "${DB_USER//%/\\x}")
    DB_PASSWORD=$(printf '%b' "${DB_PASSWORD//%/\\x}")
}

if [ -n "${DATABASE_URL:-}" ]; then
    parse_database_url "${DATABASE_URL}"
else
    DB_HOST="${POSTGRESQL_HOST:-}"
    DB_PORT="${POSTGRESQL_PORT:-5432}"
    DB_NAME="${POSTGRESQL_DATABASE:-}"
    DB_USER="${POSTGRESQL_USERNAME:-}"
    DB_PASSWORD="${POSTGRESQL_PASSWORD:-}"
fi

# -----------------------------------------------------------------------
# 2. Monta a seção [databases]
#    PGBOUNCER_DATABASES, se definida, tem prioridade total (multi-tenant
#    manual: "alias1=host=h1 port=5432 dbname=d1;alias2=host=h2 dbname=d2").
# -----------------------------------------------------------------------
DATABASES_SECTION=""
if [ -n "${PGBOUNCER_DATABASES:-}" ]; then
    log "Usando PGBOUNCER_DATABASES para múltiplos bancos"
    IFS=';' read -ra ENTRIES <<< "${PGBOUNCER_DATABASES}"
    for entry in "${ENTRIES[@]}"; do
        entry="$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$entry" ] && DATABASES_SECTION="${DATABASES_SECTION}${entry}"$'\n'
    done
elif [ -n "$DB_HOST" ]; then
    ALIAS="${PGBOUNCER_DATABASE:-*}"
    CONNSTR="host=${DB_HOST} port=${DB_PORT}"
    [ -n "$DB_NAME" ] && CONNSTR="${CONNSTR} dbname=${DB_NAME}"
    [ -n "$DB_USER" ] && CONNSTR="${CONNSTR} user=${DB_USER}"
    [ -n "$DB_PASSWORD" ] && CONNSTR="${CONNSTR} password=${DB_PASSWORD}"
    DATABASES_SECTION="${ALIAS} = ${CONNSTR}"$'\n'
else
    log "AVISO: nenhuma variável de conexão com o Postgres foi definida (DATABASE_URL ou POSTGRESQL_HOST)."
    log "Gerando pgbouncer.ini sem [databases]. Configure via PGBOUNCER_DATABASES ou monte seu próprio ini."
fi

# -----------------------------------------------------------------------
# 3. userlist.txt
#    Prioridade: PGBOUNCER_USERLIST (conteúdo bruto) > geração automática
#    a partir de POSTGRESQL_USERNAME/PASSWORD + admin/stats users.
# -----------------------------------------------------------------------
: > "$USERLIST_FILE"
if [ -n "${PGBOUNCER_USERLIST:-}" ]; then
    printf '%s\n' "${PGBOUNCER_USERLIST}" > "$USERLIST_FILE"
else
    if [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; then
        printf '"%s" "%s"\n' "$DB_USER" "$DB_PASSWORD" >> "$USERLIST_FILE"
    fi
    if [ -n "${PGBOUNCER_ADMIN_PASSWORD:-}" ]; then
        printf '"%s" "%s"\n' "${PGBOUNCER_ADMIN_USER:-pgbouncer}" "${PGBOUNCER_ADMIN_PASSWORD}" >> "$USERLIST_FILE"
    fi
fi
chmod 0600 "$USERLIST_FILE"

# -----------------------------------------------------------------------
# 4. Seção [pgbouncer]: valores nomeados com default sensato, mais um
#    escape hatch genérico via PGBOUNCER_SET_<CHAVE>=valor para qualquer
#    diretiva do pgbouncer.ini que não tenha uma variável dedicada.
# -----------------------------------------------------------------------
ADMIN_USERS="${PGBOUNCER_ADMIN_USERS:-${PGBOUNCER_ADMIN_USER:-pgbouncer}}"

{
    echo "[databases]"
    printf '%s' "$DATABASES_SECTION"
    echo
    echo "[pgbouncer]"
    echo "listen_addr = ${PGBOUNCER_BIND_ADDRESS:-0.0.0.0}"
    echo "listen_port = ${PGBOUNCER_PORT:-6432}"
    [ -n "${PGBOUNCER_UNIX_SOCKET_DIR:-}" ] && echo "unix_socket_dir = ${PGBOUNCER_UNIX_SOCKET_DIR}"
    echo "auth_type = ${PGBOUNCER_AUTH_TYPE:-scram-sha-256}"
    echo "auth_file = ${USERLIST_FILE}"
    [ -n "${PGBOUNCER_AUTH_USER:-}" ] && echo "auth_user = ${PGBOUNCER_AUTH_USER}"
    [ -n "${PGBOUNCER_AUTH_QUERY:-}" ] && echo "auth_query = ${PGBOUNCER_AUTH_QUERY}"
    echo "admin_users = ${ADMIN_USERS}"
    [ -n "${PGBOUNCER_STATS_USERS:-}" ] && echo "stats_users = ${PGBOUNCER_STATS_USERS}"
    echo "pool_mode = ${PGBOUNCER_POOL_MODE:-transaction}"
    echo "max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN:-100}"
    echo "default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE:-20}"
    echo "min_pool_size = ${PGBOUNCER_MIN_POOL_SIZE:-0}"
    echo "reserve_pool_size = ${PGBOUNCER_RESERVE_POOL_SIZE:-0}"
    echo "reserve_pool_timeout = ${PGBOUNCER_RESERVE_POOL_TIMEOUT:-5}"
    echo "max_db_connections = ${PGBOUNCER_MAX_DB_CONNECTIONS:-0}"
    echo "max_user_connections = ${PGBOUNCER_MAX_USER_CONNECTIONS:-0}"
    echo "server_idle_timeout = ${PGBOUNCER_SERVER_IDLE_TIMEOUT:-600}"
    echo "server_lifetime = ${PGBOUNCER_SERVER_LIFETIME:-3600}"
    echo "query_timeout = ${PGBOUNCER_QUERY_TIMEOUT:-0}"
    echo "client_idle_timeout = ${PGBOUNCER_CLIENT_IDLE_TIMEOUT:-0}"
    echo "log_connections = ${PGBOUNCER_LOG_CONNECTIONS:-1}"
    echo "log_disconnections = ${PGBOUNCER_LOG_DISCONNECTIONS:-1}"
    echo "log_stats = ${PGBOUNCER_LOG_STATS:-0}"
    echo "application_name_add_host = ${PGBOUNCER_APPLICATION_NAME_ADD_HOST:-0}"
    echo "ignore_startup_parameters = ${PGBOUNCER_IGNORE_STARTUP_PARAMETERS:-extra_float_digits}"

    if [ -n "${PGBOUNCER_CLIENT_TLS_SSLMODE:-}" ]; then
        echo "client_tls_sslmode = ${PGBOUNCER_CLIENT_TLS_SSLMODE}"
        [ -n "${PGBOUNCER_CLIENT_TLS_CERT_FILE:-}" ] && echo "client_tls_cert_file = ${PGBOUNCER_CLIENT_TLS_CERT_FILE}"
        [ -n "${PGBOUNCER_CLIENT_TLS_KEY_FILE:-}" ] && echo "client_tls_key_file = ${PGBOUNCER_CLIENT_TLS_KEY_FILE}"
        [ -n "${PGBOUNCER_CLIENT_TLS_CA_FILE:-}" ] && echo "client_tls_ca_file = ${PGBOUNCER_CLIENT_TLS_CA_FILE}"
    fi
    if [ -n "${PGBOUNCER_SERVER_TLS_SSLMODE:-}" ]; then
        echo "server_tls_sslmode = ${PGBOUNCER_SERVER_TLS_SSLMODE}"
    fi

    # Escape hatch genérico: PGBOUNCER_SET_MAX_PREPARED_STATEMENTS=200
    #   -> max_prepared_statements = 200
    while IFS='=' read -r name value; do
        case "$name" in
            PGBOUNCER_SET_*)
                key="${name#PGBOUNCER_SET_}"
                key="$(echo "$key" | tr '[:upper:]' '[:lower:]')"
                echo "${key} = ${value}"
                ;;
        esac
    done < <(env)

} > "$INI_FILE"
chmod 0600 "$INI_FILE"

log "pgbouncer.ini gerado em ${INI_FILE}"

if [ "${PGBOUNCER_DEBUG_PRINT_CONFIG:-false}" = "true" ]; then
    log "--- pgbouncer.ini ---"
    cat "$INI_FILE" >&2
    log "---------------------"
fi

exec "$@"

# Configuration

All configuration is done through environment variables. The entrypoint generates `/etc/pgbouncer/pgbouncer.ini` and `/etc/pgbouncer/userlist.txt` on startup.

To skip generation and use your own config files:

```
PGBOUNCER_SKIP_CONFIG_GENERATION=true
```

Mount your `pgbouncer.ini` and `userlist.txt` to `/etc/pgbouncer/`.

---

## Database connection

These variables define which PostgreSQL backend PgBouncer connects to.

`DATABASE_URL` takes precedence over `POSTGRESQL_*`.

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | — | `postgres://user:pass@host:port/dbname` |
| `POSTGRESQL_HOST` | — | Backend host |
| `POSTGRESQL_PORT` | `5432` | Backend port |
| `POSTGRESQL_DATABASE` | — | Database name |
| `POSTGRESQL_USERNAME` | — | Database user |
| `POSTGRESQL_PASSWORD` | — | Database password |

## Databases exposed by PgBouncer

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_DATABASE` | `*` | Database alias clients use to connect. `*` accepts any name. |
| `PGBOUNCER_DATABASES` | — | Multiple databases: `alias1 = host=h1 port=5432 dbname=d1;alias2 = host=h2 dbname=d2` (semicolon-separated). Overrides `DATABASE_URL`/`POSTGRESQL_*`. |

## Network

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_PORT` | `6432` | Listening port |
| `PGBOUNCER_BIND_ADDRESS` | `0.0.0.0` | Bind address |
| `PGBOUNCER_UNIX_SOCKET_DIR` | disabled | Enable Unix socket in this directory |

## Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_AUTH_TYPE` | `scram-sha-256` | `scram-sha-256`, `md5`, `plain`, `trust`, `cert`, `any` |
| `PGBOUNCER_USERLIST` | — | Raw `userlist.txt` content. Overrides auto-generation entirely (including admin password). |
| `PGBOUNCER_AUTH_USER` | — | `auth_user` for dynamic auth queries |
| `PGBOUNCER_AUTH_QUERY` | — | `auth_query` for dynamic auth |
| `PGBOUNCER_ADMIN_USER` | `pgbouncer` | Admin console user |
| `PGBOUNCER_ADMIN_PASSWORD` | — | Admin password. **Required for admin console access.** |
| `PGBOUNCER_ADMIN_USERS` | `pgbouncer` | Comma-separated list of admin users. The database user is **not** automatically included. |
| `PGBOUNCER_STATS_USERS` | — | Read-only stats users |

> The application database user does **not** have admin console access by default. Explicitly add users via `PGBOUNCER_ADMIN_USERS` if needed.

## Pooling

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_POOL_MODE` | `transaction` | `session`, `transaction`, `statement` |
| `PGBOUNCER_MAX_CLIENT_CONN` | `100` | Max client connections |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Connections per (user, database) pair |
| `PGBOUNCER_MIN_POOL_SIZE` | `0` | Minimum pooled connections kept open |
| `PGBOUNCER_RESERVE_POOL_SIZE` | `0` | Extra connections under pressure |
| `PGBOUNCER_RESERVE_POOL_TIMEOUT` | `5` | Seconds before reserve pool activates |
| `PGBOUNCER_MAX_DB_CONNECTIONS` | `0` (unlimited) | Per-database connection limit |
| `PGBOUNCER_MAX_USER_CONNECTIONS` | `0` (unlimited) | Per-user connection limit |
| `PGBOUNCER_SERVER_IDLE_TIMEOUT` | `600` | Close idle backend connections after N seconds |
| `PGBOUNCER_SERVER_LIFETIME` | `3600` | Max backend connection lifetime (seconds) |
| `PGBOUNCER_QUERY_TIMEOUT` | `0` (disabled) | Query timeout (seconds) |
| `PGBOUNCER_CLIENT_IDLE_TIMEOUT` | `0` (disabled) | Client idle timeout (seconds) |

## Logging

| Variable | Default |
|----------|---------|
| `PGBOUNCER_LOG_CONNECTIONS` | `1` |
| `PGBOUNCER_LOG_DISCONNECTIONS` | `1` |
| `PGBOUNCER_LOG_STATS` | `0` |

## TLS

| Variable | Description |
|----------|-------------|
| `PGBOUNCER_CLIENT_TLS_SSLMODE` | `require`, `allow`, `verify-full`, etc. |
| `PGBOUNCER_CLIENT_TLS_CERT_FILE` | Client cert path |
| `PGBOUNCER_CLIENT_TLS_KEY_FILE` | Client key path |
| `PGBOUNCER_CLIENT_TLS_CA_FILE` | Client CA path |
| `PGBOUNCER_SERVER_TLS_SSLMODE` | TLS mode for backend connection |

## Generic escape hatch

Any `PGBOUNCER_SET_<KEY>` variable produces `<key> = <value>` in the `[pgbouncer]` section. This covers any directive without a dedicated variable:

```bash
PGBOUNCER_SET_MAX_PREPARED_STATEMENTS=200
PGBOUNCER_SET_SERVER_RESET_QUERY="DISCARD ALL"
```

Full list of directives: https://www.pgbouncer.org/config.html

## Debug

| Variable | Description |
|----------|-------------|
| `PGBOUNCER_DEBUG_PRINT_CONFIG` | Print generated `pgbouncer.ini` to startup logs (may leak passwords) |

## Examples

```bash
docker run -d --name pgbouncer \
  -e DATABASE_URL="postgres://app:secret@pg:5432/mydb" \
  -e PGBOUNCER_ADMIN_PASSWORD="admin123" \
  -p 6432:6432 \
  ghcr.io/lucaswilliameufrasio/pgbouncer-docker:latest
```

### Multiple backends

```bash
docker run -d --name pgbouncer \
  -e PGBOUNCER_DATABASES="app1 = host=pg1 port=5432 dbname=app1;app2 = host=pg2 port=5432 dbname=app2" \
  -e PGBOUNCER_USERLIST='"app1_user" "pass1"
"app2_user" "pass2"' \
  -p 6432:6432 \
  ghcr.io/lucaswilliameufrasio/pgbouncer-docker:latest
```

### Admin console

```bash
psql -h localhost -p 6432 -U pgbouncer pgbouncer
# then: SHOW POOLS; SHOW STATS; SHOW CLIENTS;
```

### docker-compose

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: mydb

  pgbouncer:
    image: ghcr.io/lucaswilliameufrasio/pgbouncer-docker:latest
    depends_on: [postgres]
    ports: ["6432:6432"]
    environment:
      POSTGRESQL_HOST: postgres
      POSTGRESQL_DATABASE: mydb
      POSTGRESQL_USERNAME: app
      POSTGRESQL_PASSWORD: secret
      PGBOUNCER_DATABASE: mydb
      PGBOUNCER_ADMIN_PASSWORD: admin123
```

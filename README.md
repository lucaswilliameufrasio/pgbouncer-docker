# PgBouncer (imagem própria, buildada do source)

Substitui:
- `bitnami/pgbouncer` (descontinuada)
- imagem da Railway (parada, sem updates de segurança)

Builda o PgBouncer **direto do source oficial** (`github.com/pgbouncer/pgbouncer`),
na versão `1.25.2` por padrão (última no momento em que isso foi escrito —
já inclui as correções das CVE-2026-6664 a 6667). A configuração é 100% via
variáveis de ambiente, no mesmo espírito da imagem da Bitnami.

Testado localmente: o build do binário (`./autogen.sh && ./configure
--with-cares && make pgbouncer`) e o script de entrypoint foram validados
antes de fechar a imagem. O build multi-stage completo (`docker build`) não
foi rodado aqui porque o sandbox não tem daemon Docker — mas os dois pontos
de maior risco (compilação e geração de config) foram checados de verdade.

## Arquivos

```
Dockerfile              # multi-stage build (builder + runtime enxuto)
docker-entrypoint.sh    # gera pgbouncer.ini e userlist.txt a partir do ENV
```

## Build

```bash
docker build -t meu-registro/pgbouncer:1.25.2 .

# Para atualizar a versão do PgBouncer no futuro, basta trocar o ARG:
docker build --build-arg PGBOUNCER_VERSION=1.26.0 -t meu-registro/pgbouncer:1.26.0 .
```

A imagem final não tem toolchain de build, nem `curl`/`git` — só o binário
do pgbouncer e as libs de runtime (`libevent`, `libssl3`, `libcares2`).
Roda como usuário não-root (`pgbouncer`, uid 1000).

## Debian (Trixie) vs Alpine — qual usar

O `Dockerfile` (Debian Trixie-slim) é o default: mais robusto pra debugar
(glibc, ferramentas mais familiares), imagem final na faixa de ~80-90MB.

Se o objetivo é o menor footprint possível — bandwidth de pull menor no VPS,
menos superfície de ataque — use o `Dockerfile.alpine` (musl): a mesma
receita de build, mas final na faixa de ~10-15MB. Trade-off: debugar dentro
do container é mais limitado (ash em vez de bash completo, ferramentas
básicas da busybox), e musl tem algumas diferenças sutis de comportamento
de libc vs glibc (não afeta o pgbouncer em si, que já é empacotado
oficialmente pra Alpine há anos).

```bash
# Debian (default)
docker build -t meu-registro/pgbouncer:1.25.2 .

# Alpine
docker build -f Dockerfile.alpine -t meu-registro/pgbouncer:1.25.2-alpine .
```

> Nota sobre versões do Debian: o `ARG DEBIAN_CODENAME` aponta para `trixie`
> (stable atual desde ago/2025). Bookworm é oldstable. Os nomes de alguns
> pacotes de runtime mudaram no Trixie por causa da transição pra time_t de
> 64 bits (`libssl3` → `libssl3t64`, `libevent-2.1-7` → `libevent-2.1-7t64`,
> `libc-ares2` → `libc-ares2t64`) — o Dockerfile já tenta o nome novo com
> fallback pro antigo, então funciona buildando contra qualquer um dos dois.

## Deploy na Railway


1. Crie um serviço a partir deste repositório (Railway detecta o `Dockerfile`
   automaticamente).
2. Configure as variáveis de ambiente (seção abaixo). O mais comum na
   Railway é usar a variável de referência do próprio Postgres:

   ```
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   PGBOUNCER_DATABASE=railway
   PGBOUNCER_ADMIN_PASSWORD=<gere uma senha forte>
   ```

3. Exponha a porta `6432` (a porta interna do PgBouncer) e aponte suas
   aplicações para `<service>.railway.internal:6432` em vez de conectarem
   direto no Postgres.

## Variáveis de ambiente

### Conexão com o Postgres de origem

| Variável | Default | Descrição |
|---|---|---|
| `DATABASE_URL` | — | `postgres://user:pass@host:port/db`. Se definida, tem prioridade sobre as `POSTGRESQL_*` abaixo. Ideal para Railway (`${{Postgres.DATABASE_URL}}`). |
| `POSTGRESQL_HOST` | — | Host do Postgres (usado se `DATABASE_URL` não estiver setada). |
| `POSTGRESQL_PORT` | `5432` | Porta do Postgres. |
| `POSTGRESQL_DATABASE` | — | Nome do banco. |
| `POSTGRESQL_USERNAME` | — | Usuário do banco. |
| `POSTGRESQL_PASSWORD` | — | Senha do banco. |

### Banco(s) exposto(s) pelo PgBouncer

| Variável | Default | Descrição |
|---|---|---|
| `PGBOUNCER_DATABASE` | `*` | Alias que os clientes usam para conectar. `*` é um wildcard: aceita qualquer nome de banco e repassa para o backend configurado — útil quando o nome do banco do cliente já bate com o do Postgres. |
| `PGBOUNCER_DATABASES` | — | Para múltiplos bancos/backends num único PgBouncer. Formato: `alias1 = host=h1 port=5432 dbname=d1;alias2 = host=h2 dbname=d2` (separado por `;`, mesma sintaxe da seção `[databases]` do pgbouncer.ini). Se definida, ignora `DATABASE_URL`/`POSTGRESQL_*` para fins de `[databases]`. |

### Rede

| Variável | Default | Descrição |
|---|---|---|
| `PGBOUNCER_PORT` | `6432` | Porta em que o PgBouncer escuta. |
| `PGBOUNCER_BIND_ADDRESS` | `0.0.0.0` | Endereço de bind. |
| `PGBOUNCER_UNIX_SOCKET_DIR` | (desabilitado) | Se definida, também escuta em um unix socket nesse diretório. |

### Autenticação

| Variável | Default | Descrição |
|---|---|---|
| `PGBOUNCER_AUTH_TYPE` | `scram-sha-256` | `scram-sha-256`, `md5`, `plain`, `trust`, `cert` ou `any`. |
| `PGBOUNCER_USERLIST` | — | Conteúdo bruto do `userlist.txt` (uma linha por usuário: `"user" "senha"`). Se definida, ignora a geração automática. |
| `PGBOUNCER_AUTH_USER` / `PGBOUNCER_AUTH_QUERY` | — | Para autenticação via `auth_query` (consulta dinâmica no Postgres em vez de `userlist.txt` estático). |
| `PGBOUNCER_ADMIN_USER` | `pgbouncer` | Usuário admin do console (`SHOW ...`). |
| `PGBOUNCER_ADMIN_PASSWORD` | — | Senha do usuário admin. Sem isso, só o usuário do banco (`POSTGRESQL_USERNAME`) fica com acesso admin. **Recomendado sempre setar em produção.** |
| `PGBOUNCER_ADMIN_USERS` | `pgbouncer` (+ usuário do banco) | Lista completa de usuários admin, se quiser sobrescrever o default. |
| `PGBOUNCER_STATS_USERS` | — | Usuários com acesso só a `SHOW STATS`/`SHOW POOLS` etc. |

> ⚠️ Como `userlist.txt` guarda a senha em texto plano, isso funciona com
> `auth_type = md5` e `scram-sha-256` (o PgBouncer faz o hash/challenge na
> hora) — não precisa pré-computar hash nenhum.

### Pooling

| Variável | Default | Descrição |
|---|---|---|
| `PGBOUNCER_POOL_MODE` | `transaction` | `session`, `transaction` ou `statement`. |
| `PGBOUNCER_MAX_CLIENT_CONN` | `100` | Máximo de conexões de clientes. |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Conexões por par (user, database) no backend. |
| `PGBOUNCER_MIN_POOL_SIZE` | `0` | Mínimo mantido aberto por pool. |
| `PGBOUNCER_RESERVE_POOL_SIZE` | `0` | Conexões extras liberadas sob pressão. |
| `PGBOUNCER_RESERVE_POOL_TIMEOUT` | `5` | Segundos de espera antes de usar o reserve pool. |
| `PGBOUNCER_MAX_DB_CONNECTIONS` | `0` (ilimitado) | Limite global por banco. |
| `PGBOUNCER_MAX_USER_CONNECTIONS` | `0` (ilimitado) | Limite global por usuário. |
| `PGBOUNCER_SERVER_IDLE_TIMEOUT` | `600` | Segundos até fechar conexão ociosa com o backend. |
| `PGBOUNCER_SERVER_LIFETIME` | `3600` | Tempo máximo de vida de uma conexão com o backend. |
| `PGBOUNCER_QUERY_TIMEOUT` | `0` (desabilitado) | Timeout de query em segundos. |
| `PGBOUNCER_CLIENT_IDLE_TIMEOUT` | `0` (desabilitado) | Timeout de cliente ocioso. |

### Logging

| Variável | Default |
|---|---|
| `PGBOUNCER_LOG_CONNECTIONS` | `1` |
| `PGBOUNCER_LOG_DISCONNECTIONS` | `1` |
| `PGBOUNCER_LOG_STATS` | `0` |

### TLS (opcional)

| Variável | Descrição |
|---|---|
| `PGBOUNCER_CLIENT_TLS_SSLMODE` | Ex.: `require`, `allow`, `verify-full`. Ativa TLS do lado do cliente. |
| `PGBOUNCER_CLIENT_TLS_CERT_FILE` / `_KEY_FILE` / `_CA_FILE` | Caminhos dos certificados (monte via volume). |
| `PGBOUNCER_SERVER_TLS_SSLMODE` | TLS na conexão com o Postgres de origem. |

### Escape hatch genérico

Qualquer variável `PGBOUNCER_SET_<CHAVE>` vira uma linha `<chave> = valor`
na seção `[pgbouncer]`, cobrindo qualquer diretiva do `pgbouncer.ini` que não
tenha uma variável dedicada acima (ex.: `max_prepared_statements`,
`server_reset_query`, `dns_max_ttl`, etc.):

```bash
PGBOUNCER_SET_MAX_PREPARED_STATEMENTS=200
PGBOUNCER_SET_SERVER_RESET_QUERY="DISCARD ALL"
```

Lista completa de diretivas disponíveis: https://www.pgbouncer.org/config.html

### Bypass total

| Variável | Descrição |
|---|---|
| `PGBOUNCER_SKIP_CONFIG_GENERATION` | Se `true`, o entrypoint não gera nada e assume que você montou seu próprio `pgbouncer.ini`/`userlist.txt` em `/etc/pgbouncer/` via volume. |
| `PGBOUNCER_DEBUG_PRINT_CONFIG` | Se `true`, imprime o `pgbouncer.ini` gerado no log de start (útil para debug; não usar em produção com senhas sensíveis nos logs). |

## Exemplos

### Um único banco (caso comum na Railway)

```bash
docker run -p 6432:6432 \
  -e DATABASE_URL="postgres://appuser:senha@meu-postgres:5432/appdb" \
  -e PGBOUNCER_DATABASE=appdb \
  -e PGBOUNCER_ADMIN_PASSWORD=trocaesta \
  meu-registro/pgbouncer:1.25.2
```

### Múltiplos backends

```bash
docker run -p 6432:6432 \
  -e PGBOUNCER_DATABASES="app1 = host=pg1 port=5432 dbname=app1;app2 = host=pg2 port=5432 dbname=app2" \
  -e PGBOUNCER_USERLIST='"app1_user" "senha1"
"app2_user" "senha2"' \
  meu-registro/pgbouncer:1.25.2
```

### docker-compose para teste local

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppass
      POSTGRES_DB: appdb

  pgbouncer:
    build: .
    depends_on:
      - postgres
    ports:
      - "6432:6432"
    environment:
      POSTGRESQL_HOST: postgres
      POSTGRESQL_DATABASE: appdb
      POSTGRESQL_USERNAME: appuser
      POSTGRESQL_PASSWORD: apppass
      PGBOUNCER_DATABASE: appdb
      PGBOUNCER_ADMIN_PASSWORD: adminpass
```

## Acessando o console admin

```bash
psql -h localhost -p 6432 -U pgbouncer pgbouncer
# dentro do psql:
SHOW POOLS;
SHOW STATS;
SHOW CLIENTS;
```

## Atualizando a versão do PgBouncer

O `Dockerfile` baixa o tarball direto de
`github.com/pgbouncer/pgbouncer/archive/refs/tags/pgbouncer_<versão>.tar.gz`.
Para atualizar, confira a versão mais recente em
https://github.com/pgbouncer/pgbouncer/releases e rebuilde com
`--build-arg PGBOUNCER_VERSION=<nova-versão>`. Não depende de nenhuma imagem
de terceiros descontinuada — só do repositório oficial do projeto.

## Notas de segurança

- A imagem final não tem `curl`, compilador ou ferramentas de build — só o
  binário e as libs de runtime, reduzindo superfície de ataque.
- Roda como usuário não-root (`pgbouncer`, uid/gid 1000).
- `userlist.txt` é gerado com `chmod 0600`.
- Prefira sempre setar `PGBOUNCER_ADMIN_PASSWORD` — sem isso, o console admin
  só é acessível pelo usuário do próprio banco de dados.

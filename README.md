# PgBouncer Docker

Minimal PgBouncer images built from official source, configurable via environment variables. Replaces `bitnami/pgbouncer` (discontinued) and unmaintained community images.

## Images

| Variant | Size | Registry |
|---------|------|----------|
| Debian (glibc) | ~80 MB | `ghcr.io/lucaswilliameufrasio/pgbouncer-docker` |
| Alpine (musl) | ~12 MB | same + `-alpine` suffix |

```bash
# pull or run
docker run --rm ghcr.io/lucaswilliameufrasio/pgbouncer-docker:latest pgbouncer --version
```

### Tags

| Debian | Alpine |
|--------|--------|
| `X.Y.Z`, `X.Y`, `X`, `latest` | `X.Y.Z-alpine`, `X.Y-alpine`, `X-alpine`, `alpine` |

Tags are updated on each release. See [docs/releasing.md](docs/releasing.md).

## Quick start

```bash
docker run -d --name pgbouncer \
  -e DATABASE_URL="postgres://user:pass@host:5432/db" \
  -e PGBOUNCER_ADMIN_PASSWORD="<secret>" \
  -p 6432:6432 \
  ghcr.io/lucaswilliameufrasio/pgbouncer-docker:latest
```

Clients connect to port `6432`. Authenticate as any user listed in `userlist.txt` (auto-generated from `DATABASE_URL` credentials).

## Railway

```bash
DATABASE_URL=${{Postgres.DATABASE_URL}}
PGBOUNCER_DATABASE=railway
PGBOUNCER_ADMIN_PASSWORD=<secret>
```

## Security

- Non-root user (`pgbouncer`, uid 1000)
- Generated config files: `chmod 0600`, `umask 077`
- Source tarball verified by SHA-256 checksum
- Runtime image has no build tools or package manager
- Application user has **no** admin console access
- Sigstore keyless signatures and SPDX SBOM attestations (`cosign verify`) — see [docs/releasing.md](docs/releasing.md#verifying-an-image)
- SLSA provenance v1.0 attached to every pushed image

## Configuration

See [docs/configuration.md](docs/configuration.md) for all supported environment variables.

## Release process

See [docs/releasing.md](docs/releasing.md) for tag workflow and multi-architecture builds.

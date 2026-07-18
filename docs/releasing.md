# Release process

The project uses three GitHub Actions workflows: CI, Release, and an upstream version checker.

## CI

Triggered on every pull request and push to `main`. Builds all 4 variants natively (Debian amd64, Debian arm64, Alpine amd64, Alpine arm64) and runs integration tests against a real PostgreSQL container.

Does not require any credentials. Safe for public forks.

## Upstream version check

Scheduled every Monday 06:23 UTC. Queries `pgbouncer/pgbouncer` latest release. If a new stable version is found, opens a PR updating `VERSION`, `Dockerfile`, and `Dockerfile.alpine`.

CI does not automatically run on these PRs (created by `GITHUB_TOKEN`). Close and reopen to trigger it, or push a commit manually.

After the PR is merged, a maintainer creates the release tag:

```bash
git tag v$(cat VERSION)
git push origin v$(cat VERSION)
```

## Creating a release

Only the repository owner should create release tags. The tag must match `VERSION` exactly.

```bash
# verify current version
cat VERSION

# create and push tag
git tag v$(cat VERSION)
git push origin v$(cat VERSION)
```

The `Release` workflow then runs.

## Release workflow

Validates the tag, then builds and publishes multi-architecture images.

### Validation

1. Tag format: `vMAJOR.MINOR.PATCH`
2. Tag version matches `VERSION` file
3. Tag commit is an ancestor of `origin/main`

### Build

Four parallel native builds, no emulation:

| Job | Runner | Target |
|-----|--------|--------|
| Debian amd64 | `ubuntu-24.04` | `linux/amd64` |
| Debian arm64 | `ubuntu-24.04-arm` | `linux/arm64` |
| Alpine amd64 | `ubuntu-24.04` | `linux/amd64` |
| Alpine arm64 | `ubuntu-24.04-arm` | `linux/arm64` |

Each job pushes its single-arch image to GHCR with a unique tag.

### Manifest merge

After all builds succeed, two manifest jobs run:

```
Debian:  amd64 digest + arm64 digest  →  X.Y.Z, X.Y, X, latest
Alpine:  amd64 digest + arm64 digest  →  X.Y.Z-alpine, X.Y-alpine, X-alpine, alpine
```

### GHCR visibility

Since the source repository is **private**, the GHCR package inherits private visibility. To make images publicly accessible:

1. Go to package settings at `https://github.com/users/<owner>/packages/container/<package>/settings`
2. Change visibility to **Public**
3. Disable **"Inherit access from repository"** if you want granular control

> GitHub Free accounts cannot use environment required reviewers on private repositories. The tag creation itself acts as the approval gate — only users with write access can push tags.

## Out-of-cycle releases

For emergency releases (e.g., a new PgBouncer patch before the weekly check runs):

1. Update `VERSION` manually with the new version
2. Update `Dockerfile` and `Dockerfile.alpine`: `PGBOUNCER_VERSION` and `PGBOUNCER_SHA256`
3. Commit and push to `main`
4. Create and push the tag

# Release process

The project uses three GitHub Actions workflows: CI, Release, and an upstream version checker.

## CI

Triggered on every pull request and push to `main`. Builds all 4 variants natively (Debian amd64, Debian arm64, Alpine amd64, Alpine arm64) and runs integration tests against a real PostgreSQL container.

Does not require any credentials. Safe for public forks.

## Upstream version check

Scheduled every Monday 06:23 UTC. Queries `pgbouncer/pgbouncer` latest release. If a new stable version is found, opens a PR updating `VERSION`, `Dockerfile`, and `Dockerfile.alpine`.

The PR is not a suggestion-only artifact: the workflow dispatches the **full CI pipeline** (`workflow_dispatch` on `ci.yml`) against the update branch and waits for it. Build, smoke tests, and PostgreSQL integration tests run exactly as they would on a manual PR. The result is posted as a PR comment, and the update workflow fails if CI fails.

> CI cannot trigger on the PR itself (created by `GITHUB_TOKEN`, to prevent recursion), so the workflow dispatches it explicitly and gates on the result.

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

### Provenance, SBOM, and signing

Every released image ships with supply-chain metadata:

| Artifact | Attached by | Content |
|----------|-------------|---------|
| SLSA provenance v1.0 (`mode=max`) | BuildKit (`provenance`) | Build definition, source commit, builder identity |
| SPDX SBOM (in-toto attestation) | BuildKit (`sbom`) | Package inventory per architecture |
| SBOM SPDX attestation | `cosign attest` (`spdxjson`) | Syft-generated SBOM of the final multi-arch index |
| Keyless signature | `cosign sign` | Sigstore signature on the multi-arch index digest |

The signing job runs last, after both manifest merges. It resolves the multi-arch index digest, signs it keyless with the GitHub Actions OIDC identity, attests the SBOM, and then verifies everything back — a failed verification fails the release.

Signatures and attestations are stored as referrers in GHCR. SLSA provenance and BuildKit SBOMs live on the per-architecture indexes (tagged `X.Y.Z-linux-amd64`, etc.); the `cosign` signature and SBOM attestation cover the final index digest that the public tags point to.

#### Verifying an image

Consumers can verify before pulling (requires [cosign](https://github.com/sigstore/cosign)):

```bash
IMAGE=ghcr.io/lucaswilliameufrasio/pgbouncer-docker
DIGEST=$(docker buildx imagetools inspect $IMAGE:latest --format '{{.Manifest.Digest}}')

# signature
cosign verify \
  --certificate-identity-regexp '^https://github.com/lucaswilliameufrasio/pgbouncer-docker/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  $IMAGE@$DIGEST

# SBOM attestation
cosign verify-attestation --type spdxjson \
  --certificate-identity-regexp '^https://github.com/lucaswilliameufrasio/pgbouncer-docker/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  $IMAGE@$DIGEST
```

Keyless verification means no key management on the maintainer side: the trust anchor is the GitHub OIDC issuer and the workflow path, and tampering with the workflow changes the identity.

> Releases published via manual `workflow_dispatch` run on `main`, so their signatures carry identity `@refs/heads/main` instead of `@refs/tags/v…`. Broaden the regexp to `(tags/v[0-9.]+|heads/main)` if you need to verify those.

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

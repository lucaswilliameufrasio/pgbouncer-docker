# syntax=docker/dockerfile:1

ARG PGBOUNCER_VERSION=1.26.0
ARG PGBOUNCER_SHA256=afd25dd61ee6775d37b40629b87ce08736b3e6955f3057bb212e410fbf21c71d
ARG DEBIAN_CODENAME=trixie

FROM debian:${DEBIAN_CODENAME}-slim AS builder

ARG PGBOUNCER_VERSION
ARG PGBOUNCER_SHA256

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        libevent-dev \
        libssl-dev \
        libc-ares-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN set -e; \
    VERSION_TAG="$(printf '%s' "${PGBOUNCER_VERSION}" | tr '.' '_')"; \
    url="https://github.com/pgbouncer/pgbouncer/releases/download/pgbouncer_${VERSION_TAG}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz"; \
    curl -fsSL -o pgbouncer.tar.gz "$url"; \
    echo "${PGBOUNCER_SHA256}  pgbouncer.tar.gz" | sha256sum -c -; \
    mkdir -p src; \
    tar -xzf pgbouncer.tar.gz -C src --strip-components=1; \
    rm pgbouncer.tar.gz

WORKDIR /build/src

RUN ./autogen.sh \
    && ./configure --prefix=/usr/local --with-cares --disable-debug \
    && make -j"$(nproc)" pgbouncer \
    && strip pgbouncer

FROM debian:${DEBIAN_CODENAME}-slim AS runtime

ARG PGBOUNCER_VERSION
ENV PGBOUNCER_VERSION=${PGBOUNCER_VERSION}

LABEL org.opencontainers.image.title="pgbouncer" \
      org.opencontainers.image.description="PgBouncer buildado a partir do source, configurável via variáveis de ambiente" \
      org.opencontainers.image.source="https://github.com/lucaswilliameufrasio/pgbouncer-docker" \
      org.opencontainers.image.url="https://github.com/lucaswilliameufrasio/pgbouncer-docker" \
      org.opencontainers.image.version="${PGBOUNCER_VERSION}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates \
    && ( apt-get install -y --no-install-recommends libevent-2.1-7t64 \
         || apt-get install -y --no-install-recommends libevent-2.1-7 ) \
    && ( apt-get install -y --no-install-recommends libssl3t64 \
         || apt-get install -y --no-install-recommends libssl3 ) \
    && ( apt-get install -y --no-install-recommends libc-ares2t64 \
         || apt-get install -y --no-install-recommends libc-ares2 ) \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 pgbouncer \
    && useradd --system --uid 1000 --gid pgbouncer --home-dir /etc/pgbouncer --shell /usr/sbin/nologin pgbouncer \
    && mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer \
    && chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer

COPY --from=builder /build/src/pgbouncer /usr/local/bin/pgbouncer
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/pgbouncer

USER pgbouncer
WORKDIR /etc/pgbouncer

EXPOSE 6432

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_PORT:-6432}' 2>/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]

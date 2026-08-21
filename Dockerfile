# syntax=docker/dockerfile:1
#
# Self-hosted, minimal FUTU OpenD image.
#
# The OpenD binary ships as an Ubuntu 18.04 (bionic) tarball, so:
#   - A build stage on ubuntu:22.04 (whose apt works reliably) downloads,
#     verifies, and unpacks the archive.
#   - The runtime stage runs on ubuntu:24.04. The binary is dynamically linked
#     but ships its own libssl/libcurl/libprotobuf, so it only needs the
#     standard glibc libs present on 24.04 (see versions.json notes).
#
# Security posture (see the deployment plan):
#   - The official archive is verified over TLS *and* by the SHA256 in
#     versions.json before it is unpacked; `curl -k` is never used.
#   - Only the command-line OpenD files are copied over — no GUI installer.
#   - Runs as a non-root `futu` user, read-only rootfs (state and /tmp are the
#     only writable mounts), all capabilities dropped, no-new-privileges.
#   - No default password and no image-shipped credentials; no ports published.
#
# CI can override these build arguments for release artifacts. Their defaults
# make local and CI builds self-contained, without an image-digest environment
# variable.
# Keep them in sync with versions.json.

# Global build args used inside a FROM (must be declared before any FROM).
ARG FUTU_RUNTIME_DIGEST=sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

# ---- Build stage: download + verify + unpack on a working ubuntu ---------
FROM ubuntu:22.04 AS build
ARG OPEND_VERSION=10.9.6918
ARG OPEND_ARCHIVE_URL=https://softwaredownload.futunn.com/Futu_OpenD_10.9.6918_Ubuntu18.04.tar.gz
ARG OPEND_ARCHIVE_SHA256=37d95a2b302b50189e5eb464869d3bc364d2f5d8b466144f00d6a560d266c0b3

RUN set -eu; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
# Verify TLS + checksum BEFORE unpacking. `curl -k` is never used and the
# build refuses to proceed unless sha256sum matches the manifest.
RUN set -eu; \
    # The FUTU CDN intermittently resets long HTTP/2 downloads. Use HTTP/1.1
    # and resume-capable retries while retaining TLS and checksum validation.
    curl --fail --proto '=https' --tlsv1.2 --http1.1 --location \
         --retry 5 --retry-all-errors --retry-delay 5 --continue-at - \
         --output opend.tar.gz "$OPEND_ARCHIVE_URL"; \
    echo "$OPEND_ARCHIVE_SHA256  opend.tar.gz" | sha256sum -c -; \
    mkdir -p unpack; \
    tar -xzf opend.tar.gz -C unpack; \
    rm -rf opend.tar.gz

# The tarball unpacks to a per-version directory containing the FutuOpenD
# binary and its sibling libraries.
ARG OPEND_VERSION
# The official archive nests a same-named directory one level deep, so a
# shallow `find -maxdepth 1` matches the wrapper dir instead of the one that
# actually holds the FutuOpenD binary. Locate the directory containing an
# executable FutuOpenD instead (works for both flat and nested layouts).
RUN dir="$(find /tmp/unpack -type d -name 'Futu_OpenD*' -exec test -x '{}/FutuOpenD' \; -print -quit)" \
    && test -n "$dir" \
    && test -x "$dir/FutuOpenD" \
    && cp -a "$dir" /opt/futu-opend

# ---- Runtime stage: Ubuntu 24.04 (binary compat) --------------------------
FROM ubuntu@${FUTU_RUNTIME_DIGEST} AS runtime

ARG OPEND_VERSION

ENV OPEND_HOME=/opt/futu-opend \
    OPEND_USER_HOME=/home/futu

RUN set -eu; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libstdc++6 \
        libgcc-s1 \
        libglib2.0-0t64 \
        locales \
        bash \
        findutils \
        openssl \
        procps \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/futu-opend "$OPEND_HOME"
COPY entrypoint.sh /usr/local/bin/futu-entrypoint

RUN set -eu; \
    groupadd --gid 10002 futu; \
    useradd --create-home --uid 10002 --gid 10002 futu; \
    mkdir -p "$OPEND_USER_HOME/.com.futunn.FutuOpenD"; \
    chown -R futu:futu "$OPEND_USER_HOME"; \
    # ~/.futu is OpenD's home config dir (RSA + per-run state); keep it owned
    # by the operator.
    mkdir -p "$OPEND_USER_HOME/.futu"; \
    chown -R futu:futu "$OPEND_USER_HOME"; \
    chmod 0755 /usr/local/bin/futu-entrypoint

# /tmp must be writable for the rendered XML config; under Compose a tmpfs is
# mounted there. The image remains non-root and no state recipes are baked in.
USER futu
WORKDIR $OPEND_USER_HOME

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# No default password and no EXPOSE. FUTU_ACCOUNT_ID, FUTU_ACCOUNT_PWD_MD5_FILE,
# FUTU_RSA_KEY_FILE, and FUTU_OPEND_* are consumed by the entrypoint.

ENTRYPOINT ["/usr/local/bin/futu-entrypoint"]

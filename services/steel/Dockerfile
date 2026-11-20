# syntax=docker/dockerfile:1
#
# Steel Browser (steel-dev, Apache-2.0) behind an access-token gateway, for Railway.
#
# Base: steel-dev's combined image (API + web UI + Chromium), the build of
# main at commit 161d259d (2026-11-19, after release v0.5.5-beta). steel-dev
# publishes only a moving "latest" tag, so the image is pinned by its
# multi-arch index digest. To upgrade, take the new digest of
# ghcr.io/steel-dev/steel-browser:latest and redeploy.
FROM ghcr.io/steel-dev/steel-browser:latest@sha256:e10ce7adecc94d000b28d256c45ffa113dc78b4fc8d38de5f7940b139c3a220d

COPY --chmod=0755 railway-start.sh /usr/local/bin/railway-start

# The image ships nginx (used here for the gateway), tini and bash.
RUN set -eux; \
  command -v nginx; command -v tini; bash --version | head -n 1; \
  test -f /app/api/build/index.js; \
  bash -n /usr/local/bin/railway-start

ENV PORT=8080 \
    NODE_ENV=production \
    CHROME_HEADLESS=true \
    LOG_STORAGE_ENABLED=true \
    LOG_STORAGE_PATH=/data/logs/browser-logs.duckdb

EXPOSE 8080
WORKDIR /app

# Railway runs its own init as PID 1, so tini runs as a subreaper (-s).
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/railway-start"]

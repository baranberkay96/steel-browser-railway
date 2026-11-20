# NOTICE: Steel Browser template

This is a community template. It is not made, endorsed or supported by Steel (steel-dev) or Railway.

## Components

| Component | Source | License | How it is used |
|---|---|---|---|
| Steel Browser, image `ghcr.io/steel-dev/steel-browser:latest@sha256:e10ce7adecc94d000b28d256c45ffa113dc78b4fc8d38de5f7940b139c3a220d` (built 2026-11-19 from main commit `161d259dd9dbdfd54d0f20137322a6d8db4a0c09`, after release `v0.5.5-beta`) | https://github.com/steel-dev/steel-browser | Apache-2.0 (Copyright Steel) | Base image (`FROM`), unmodified |
| Chromium, nginx, tini and other Debian packages in that image | https://packages.debian.org/ | Each package's own license | Inside the base image; the template uses its nginx for the gateway |
| Node.js 22 (`node:22` base of the Steel image) | https://nodejs.org/ | MIT | Inside the base image |

Steel Browser is licensed under the Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0). The image is used as published; no Steel source file is copied into this repository and none is modified. Steel's `api/entrypoint.sh` is replaced as the entrypoint by `railway-start.sh`, which starts the same program (`node ./api/build/index.js` in `/app`) with Steel's own environment variables.

## Files written for this template

`services/steel/Dockerfile`, `services/steel/railway-start.sh` (token gateway, loopback binding, log-size cap, process supervision) and the documentation are offered under the Apache License 2.0. The gateway follows the design of our own Moli and Obscura headless-browser templates (token as bearer, header, query or Basic-auth password; unauthenticated health path).

## Upstream files checked

At commit `161d259d` / tag `v0.5.5-beta`: `Dockerfile`, `docker-compose.yml`, `render.yaml`, `.env.example`, `api/entrypoint.sh`, `api/nginx.conf`, `api/src/env.ts` (HOST, PORT, DOMAIN, USE_SSL, CDP_*, LOG_STORAGE_*), `api/src/services/cdp/cdp.service.ts` (DevTools bound to `HOST`, `--no-sandbox` as root), `api/src/plugins/browser-socket/browser-socket.ts` (CDP WebSocket on the API port), `.github/workflows/build-docker.yml` (only a `latest` tag is published).

## Market templates

The three Steel templates on the Railway marketplace were reviewed for features only. All three expose Steel without authentication and use the moving `latest` tag. No files or text were copied.

## Railway Fair Use

Railway's Fair Use Policy forbids proxies and VPN exits, scraping that violates websites' terms, abusive bots, cryptocurrency mining and reselling compute. This template ships no proxy, CAPTCHA-solving or stealth add-on beyond what Steel itself includes.

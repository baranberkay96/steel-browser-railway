# TEMPLATE: Steel Browser API for AI Agents (Token-Protected)

Composer spec. `template.json` is the machine-readable copy.

## Service

| Field | Value |
|---|---|
| Name | Steel Browser |
| Source | repo `baranberkay96/steel-browser-railway`, root `/services/steel` |
| Base | `ghcr.io/steel-dev/steel-browser:latest@sha256:e10ce7ad…` (2026-11-19, main `161d259d`, after v0.5.5-beta) |
| Public domain | yes, target port 8080 (nginx token gateway) |
| Healthcheck | `/health` (no token; proxies Steel `/v1/health`), timeout 300 s |
| Restart | ALWAYS |
| Volume | `/data` (DuckDB session event log) |

Variables: `STEEL_API_TOKEN` (`secret(48)` alphanumeric), `PORT` (8080), `DOMAIN` (`RAILWAY_PUBLIC_DOMAIN`), `USE_SSL` (true), `CHROME_HEADLESS` (true), `LOG_STORAGE_ENABLED` (true), `LOG_STORAGE_MAX_MB` (1024), `PROXY_URL`, `STEEL_BASE_URL`, `STEEL_WS_ENDPOINT`.

## Improvements over market templates

- Token gateway: market templates expose Steel's API, CDP and UI without any authentication.
- Steel API and Chromium DevTools bound to 127.0.0.1 (not reachable from the private network either); CDP proxy port 9223 on loopback.
- Image pinned by digest instead of `latest`.
- Invalid or missing token locks the API with a random token; the deploy still succeeds (STANDARD 8.29).
- Basic-auth requests from other websites refused (Origin check); anti-framing headers.
- Session event log capped at start; volume at `/data`.
- Convenience variables `STEEL_BASE_URL` and `STEEL_WS_ENDPOINT` for other services.

## Resources

| Service | Idle RAM | Typical RAM | CPU |
|---|---|---|---|
| Steel Browser | ~0.55 GB measured | 0.6–1.5 GB with an active session | near 0 idle, 0.5–1 vCPU per busy session |

Estimated cost: $3–10/month idle to light use. Minimum plan: Trial works for single sessions; Hobby recommended.

## Verification checklist

- `/health` 200 without token; `/v1/sessions` 401 without, 200 with token (bearer, `steel-api-key`, `?token=`, Basic `steel`).
- `POST /v1/scrape` or `/v1/screenshot` for https://example.com returns content.
- Basic auth with a foreign `Origin` → 403.
- Short token in `STEEL_API_TOKEN` → deploy healthy, API locked.

## Open questions

- steel-dev publishes only `latest`; if GHCR ever prunes the pinned digest, builds fail until the digest is bumped.

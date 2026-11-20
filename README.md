# Deploy and Host Steel Browser with Railway

Steel Browser is an open-source browser API for AI agents and automation: it starts Chromium sessions on request and lets Puppeteer, Playwright, Selenium or the Steel SDK drive them, with a live session viewer and event logs. This template runs it on Railway behind an access token, because Steel itself has no login.

## About Hosting Steel Browser

Steel Browser (Apache-2.0, by steel-dev) is a Node.js API that manages a Chromium instance, exposes REST endpoints for sessions, scraping actions, screenshots and PDFs, and proxies the Chrome DevTools Protocol over WebSocket. Upstream ships it without authentication, so anyone with the URL could drive the browser. This community template pins steel-dev's image by digest and puts an nginx token gateway in front: Steel's API and Chromium's DevTools port listen on 127.0.0.1 only, and every public request needs the generated token, except the `/health` endpoint that Railway's healthcheck uses. Session event logs are kept in DuckDB on a volume.

## Common Use Cases

- Give an AI agent (browser-use, Stagehand, LangChain or your own) a remote browser through the Steel SDK or CDP
- Run Puppeteer or Playwright scripts against a hosted Chromium instead of bundling a browser in every app
- Take screenshots, PDFs and page extracts of URLs through a simple REST API
- Watch and debug agent sessions live in Steel's web UI

## Dependencies for Steel Browser Hosting

- One service built from a small Dockerfile on top of `ghcr.io/steel-dev/steel-browser` (no database, no API keys)
- A Railway volume at `/data` for session event logs

### Deployment Dependencies

- [steel-dev/steel-browser on GitHub](https://github.com/steel-dev/steel-browser)
- [Steel documentation](https://docs.steel.dev/)
- [Steel Node.js SDK](https://github.com/steel-dev/steel-node) and [Python SDK](https://github.com/steel-dev/steel-python)
- [Railway Fair Use Policy](https://railway.com/legal/fair-use)

### Implementation Details

| Service | What runs inside | Volume | Port |
|---|---|---|---|
| Steel Browser | nginx token gateway on `PORT`; Steel API on 127.0.0.1:3000 with the web UI at `/ui`; Chromium (DevTools on loopback only) | `/data` | 8080 (public HTTPS domain) |

**Plan:** RAM_PLACEHOLDER

**Using the token**

`STEEL_API_TOKEN` is generated at deploy (service Variables). Every request needs it, in any one of these forms:

- `Authorization: Bearer {token}` or the header `steel-api-key: {token}` (what the Steel SDKs send)
- `?token={token}` or `?apiKey={token}` in the URL (for WebSocket clients)
- Basic auth with user `steel` and the token as password (the web UI in a browser)

Requests without a valid token get `401`. Basic-auth requests that come from another website get `403`.

**First steps**

1. Wait until the deploy is healthy, then open `https://{your-domain}/ui`. Sign in as `steel` with the token.
2. REST: `curl -H "Authorization: Bearer {token}" -X POST https://{your-domain}/v1/sessions -H "Content-Type: application/json" -d '{}'` starts a session; `POST /v1/scrape`, `/v1/screenshot` and `/v1/pdf` work on single URLs.
3. Puppeteer: `puppeteer.connect({ browserWSEndpoint: "wss://{your-domain}?token={token}" })`. Playwright: `chromium.connectOverCDP("wss://{your-domain}?token={token}")`. The full URL is in the `STEEL_WS_ENDPOINT` variable.
4. Steel SDK: create the client with `baseURL` = `STEEL_BASE_URL` and `steelAPIKey` = the token.
5. API reference: `https://{your-domain}/documentation`.

Session URLs in API answers (`websocketUrl`, `debugUrl`) do not contain the token: add `?token=` yourself, or send it as a header.

**Security notes**

- Treat the token like a password: anyone with it controls the browser, including pages that are signed in.
- Pages opened in Steel can reach your project's private network (other services' `*.railway.internal` addresses). Do not point it at untrusted pages if private services in the same project have no authentication.
- Chromium runs as root with `--no-sandbox`, as in upstream's image (Railway containers cannot create the user namespaces its sandbox needs). The container is the security boundary.
- Steel's optional commands API (`ENABLE_COMMANDS_API`) stays off.

**Persistence and limits**

`/data` holds the DuckDB session event log; at each start a log larger than `LOG_STORAGE_MAX_MB` is replaced. Browser sessions, cookies and downloads are not kept across restarts unless your client saves the session context through Steel's API. Steel runs one browser at a time per service: keep one replica, and deploy the template again for a second independent browser.

**Upgrades**

steel-dev only publishes a moving `latest` tag. The template pins the image digest from 2026-11-19 (commit `161d259d`, after release v0.5.5-beta). To upgrade, replace the digest in `services/steel/Dockerfile` and redeploy.

**Fair use**

Use Steel for your own automation, testing and agents. Railway's Fair Use Policy forbids proxies and VPN exits, scraping that violates websites' terms, abusive bots, cryptocurrency mining and reselling compute. Only use `PROXY_URL` with a proxy you are allowed to use.

### Why Deploy Steel Browser on Railway?

Railway runs the browser next to your agents and apps, gives it HTTPS and a volume, and bills for the RAM and CPU it actually uses. One click gives you a private, token-protected browser API instead of a shared cloud plan. This is a community template, not affiliated with Steel (steel-dev) or Railway.

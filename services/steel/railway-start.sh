#!/usr/bin/env bash
# railway-start: Steel Browser behind an access-token gateway, for Railway.
#
# Steel Browser has no authentication of its own: anyone who reaches its API
# can open browser sessions and drive them. This script therefore
#  1. checks STEEL_API_TOKEN. No value fails the deploy: without a usable
#     token (16-256 characters of A-Z a-z 0-9 . _ ~ -) the gateway gets a
#     random token nobody knows, so the API stays locked, never open;
#  2. writes an nginx gateway on $PORT (the public port) that accepts the
#     token as "Authorization: Bearer", "steel-api-key" header, ?token= or
#     ?apiKey= query, or as the Basic-auth password of user "steel" (for the
#     web UI in a browser). Basic-auth requests from other websites are
#     refused (Origin check), so a visited page cannot use a cached login.
#     /health answers without a token for Railway's healthcheck;
#  3. starts Steel's API on 127.0.0.1:3000 and its CDP proxy on
#     127.0.0.1:9223, so neither is reachable from the internet or from other
#     services on the private network except through the gateway;
#  4. supervises nginx and Steel: if either exits, the other is stopped and
#     the container exits, so Railway restarts it. SIGTERM stops both.
set -Eeuo pipefail

readonly RUN_DIR="/run/railway-steel"
readonly NGINX_CONF="${RUN_DIR}/nginx.conf"
readonly STEEL_HOST="127.0.0.1"
readonly STEEL_PORT=3000
readonly CDP_PORT=9222
readonly CDP_PROXY_PORT=9223
readonly DEFAULT_PORT=8080
readonly BASIC_USER="steel"
readonly TOKEN_PATTERN='^[A-Za-z0-9._~-]{16,256}$'
readonly DATA_DIR="/data"
readonly DEFAULT_LOG_PATH="/data/logs/browser-logs.duckdb"
readonly DEFAULT_LOG_MAX_MB=1024

NGINX_PID=""
STEEL_PID=""

log() { printf '[railway-start] %s\n' "$*" >&2; }

is_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 ))
}

validate_settings() {
  PORT="${PORT:-$DEFAULT_PORT}"
  if ! is_port "$PORT" || (( PORT == STEEL_PORT || PORT == CDP_PORT || PORT == CDP_PROXY_PORT )); then
    log "WARNING: PORT must be a free port number (not ${STEEL_PORT}, ${CDP_PORT} or ${CDP_PROXY_PORT}); got '${PORT}'. Using ${DEFAULT_PORT}."
    PORT="$DEFAULT_PORT"
  fi

  TOKEN="${STEEL_API_TOKEN:-}"
  if [[ ! "$TOKEN" =~ $TOKEN_PATTERN ]]; then
    log "WARNING: STEEL_API_TOKEN is missing, shorter than 16 characters, longer than 256 or has characters other than A-Z a-z 0-9 . _ ~ -. The API is locked with a random token nobody knows. Set STEEL_API_TOKEN in the service Variables and redeploy."
    TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  # Nothing below needs the token in the environment.
  unset STEEL_API_TOKEN
}

# DuckDB keeps every browser event; cap the file at start so the volume
# never fills up. Only the event log is removed, never anything else.
prepare_data() {
  local log_path="${LOG_STORAGE_PATH:-$DEFAULT_LOG_PATH}" max_mb="${LOG_STORAGE_MAX_MB:-$DEFAULT_LOG_MAX_MB}" size_mb
  if command -v mountpoint > /dev/null 2>&1 && ! mountpoint -q "$DATA_DIR"; then
    log "WARNING: ${DATA_DIR} is not a mounted volume. Session logs are lost on every redeploy."
  fi
  [[ "$max_mb" =~ ^[0-9]+$ ]] || { log "WARNING: LOG_STORAGE_MAX_MB must be a number of MB. Using ${DEFAULT_LOG_MAX_MB}."; max_mb="$DEFAULT_LOG_MAX_MB"; }
  install -d -m 0755 "$(dirname "$log_path")"
  if [[ -f "$log_path" ]] && (( max_mb > 0 )); then
    size_mb=$(( $(stat -c %s "$log_path") / 1048576 ))
    if (( size_mb > max_mb )); then
      log "Session event log is ${size_mb} MB (limit ${max_mb} MB): starting a new one."
      rm -f -- "$log_path" "${log_path}.wal"
    fi
  fi
  export LOG_STORAGE_PATH="$log_path"
}

listen_lines() {
  printf '    listen 0.0.0.0:%s;\n' "$PORT"
  if [[ -s /proc/net/if_inet6 ]]; then
    printf '    listen [::]:%s;\n' "$PORT"
  fi
}

write_nginx_conf() {
  local basic
  basic="$(printf '%s:%s' "$BASIC_USER" "$TOKEN" | base64 -w0)"
  install -d -m 0700 "$RUN_DIR" "${RUN_DIR}/tmp"
  (
    umask 0077
    cat > "$NGINX_CONF" << EOF
worker_processes 2;
pid ${RUN_DIR}/nginx.pid;
error_log stderr warn;
events { worker_connections 1024; }
http {
  access_log off;
  server_tokens off;
  client_max_body_size 200m;
  client_body_temp_path ${RUN_DIR}/tmp/body;
  proxy_temp_path ${RUN_DIR}/tmp/proxy;
  fastcgi_temp_path ${RUN_DIR}/tmp/fastcgi;
  uwsgi_temp_path ${RUN_DIR}/tmp/uwsgi;
  scgi_temp_path ${RUN_DIR}/tmp/scgi;

  map \$http_upgrade \$gw_connection { default upgrade; '' ''; }
  map \$http_authorization \$gw_auth_header { default 0; "Bearer ${TOKEN}" 1; "Basic ${basic}" 2; }
  map \$http_steel_api_key \$gw_auth_steel { default 0; "${TOKEN}" 1; }
  map \$arg_token \$gw_auth_arg { default 0; "${TOKEN}" 1; }
  map \$arg_apiKey \$gw_auth_apikey { default 0; "${TOKEN}" 1; }
  map \$http_origin \$gw_origin_host {
    "" "-";
    "~^https?://(?<gw_origin_name>[^/:]+)(:[0-9]+)?/?\$" \$gw_origin_name;
    default "!invalid";
  }
  map "\$gw_auth_header\$gw_auth_steel\$gw_auth_arg\$gw_auth_apikey:\$gw_origin_ok" \$gw_decision {
    "~^(1...|.1..|..1.|...1):" allow;
    "~^2...:1\$" allow;
    "~^2...:0\$" forbid;
    default deny;
  }

  server {
${LISTEN_LINES}
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Content-Security-Policy "frame-ancestors 'self'" always;

    location = /health {
      limit_except GET { deny all; }
      proxy_pass http://${STEEL_HOST}:${STEEL_PORT}/v1/health;
      proxy_connect_timeout 5s;
      proxy_read_timeout 10s;
    }

    location / {
      set \$gw_origin_ok 0;
      if (\$gw_origin_host = "-") { set \$gw_origin_ok 1; }
      if (\$gw_origin_host = \$host) { set \$gw_origin_ok 1; }
      if (\$gw_decision = forbid) { return 403; }
      if (\$gw_decision = deny) {
        add_header WWW-Authenticate 'Basic realm="Steel Browser", charset="UTF-8"' always;
        return 401;
      }
      proxy_pass http://${STEEL_HOST}:${STEEL_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$gw_connection;
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header Authorization "";
      proxy_set_header steel-api-key "";
      proxy_buffering off;
      proxy_request_buffering off;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }

  server {
    listen 127.0.0.1:${CDP_PROXY_PORT};
    location / {
      proxy_pass http://127.0.0.1:${CDP_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$gw_connection;
      proxy_set_header Host \$host;
      proxy_buffering off;
      proxy_read_timeout 86400s;
    }
  }
}
EOF
  )
  nginx -t -q -c "$NGINX_CONF" || { log "ERROR: nginx rejected the gateway configuration."; exit 1; }
}

# shellcheck disable=SC2329 # called from the signal trap
on_signal() {
  trap - TERM INT
  log "Stopping Steel Browser and the gateway."
  [[ -z "$STEEL_PID" ]] || kill -TERM "$STEEL_PID" 2> /dev/null || true
  [[ -z "$NGINX_PID" ]] || kill -QUIT "$NGINX_PID" 2> /dev/null || true
  wait 2> /dev/null || true
  exit 0
}

main() {
  trap on_signal TERM INT
  validate_settings
  prepare_data
  LISTEN_LINES="$(listen_lines)"
  write_nginx_conf
  unset TOKEN

  nginx -c "$NGINX_CONF" -g 'daemon off;' &
  NGINX_PID=$!

  # Steel reads HOST and PORT for its API and binds Chromium's DevTools to
  # HOST as well; both stay on loopback. Public URLs in API answers use DOMAIN.
  local domain="${DOMAIN:-${RAILWAY_PUBLIC_DOMAIN:-localhost:${PORT}}}"
  (
    cd /app
    exec env HOST="$STEEL_HOST" PORT="$STEEL_PORT" DOMAIN="$domain" \
      USE_SSL="${USE_SSL:-true}" CDP_REDIRECT_PORT="$CDP_PROXY_PORT" \
      CDP_DOMAIN="${CDP_DOMAIN:-${STEEL_HOST}:${CDP_PROXY_PORT}}" DISPLAY="${DISPLAY:-:10}" \
      node ./api/build/index.js
  ) &
  STEEL_PID=$!
  log "Steel Browser API at https://${domain}/ (token required; web UI at /ui, user '${BASIC_USER}', password = STEEL_API_TOKEN)."

  local status=0
  wait -n "$NGINX_PID" "$STEEL_PID" || status=$?
  if ! kill -0 "$NGINX_PID" 2> /dev/null; then
    log "nginx exited (status ${status}). Stopping so Railway restarts the service."
  else
    log "Steel Browser exited (status ${status}). Stopping so Railway restarts the service."
  fi
  kill -TERM "$STEEL_PID" 2> /dev/null || true
  kill -QUIT "$NGINX_PID" 2> /dev/null || true
  wait 2> /dev/null || true
  exit 1
}

main "$@"

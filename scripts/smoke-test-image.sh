#!/usr/bin/env bash
# Starts the image in front of stub frontend and backend upstreams and checks where each
# route ends up. The stubs run the image under test with their own config, so no other
# image is pulled.
# Usage: scripts/smoke-test-image.sh <image>
set -euo pipefail

image="${1:?usage: $0 <image>}"
network="proxy-smoke-$$"
tmp=$(mktemp -d)
containers=()

cleanup() {
  if [ "${#containers[@]}" -gt 0 ]; then
    docker rm -f "${containers[@]}" >/dev/null 2>&1 || true
  fi
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "FAIL $*" >&2
  if [ -n "${proxy:-}" ]; then
    docker logs "$proxy" >&2 || true
  fi
  exit 1
}

# stub <name>: an upstream reachable as <name> on ports 80 and 8080 that answers every
# request with its own name and the request details the proxy is responsible for.
stub() {
  local name=$1 id
  cat >"$tmp/$name.conf" <<EOF
events {}
http {
  server {
    listen 80;
    listen 8080;
    location / {
      default_type text/plain;
      return 200 "$name uri=\$request_uri upgrade=\$http_upgrade connection=\$http_connection\n";
    }
  }
}
EOF
  id=$(docker create --network "$network" --network-alias "$name" --entrypoint nginx "$image" \
    -g 'daemon off;' -c /stub.conf)
  containers+=("$id")
  docker cp "$tmp/$name.conf" "$id:/stub.conf" >/dev/null
  docker start "$id" >/dev/null
}

# check <path> <expected status> [expected pattern in headers+body]
# Extra curl arguments can be given through CURL_ARGS.
check() {
  local path=$1 status=$2 pattern=${3:-} response
  # shellcheck disable=SC2086
  response=$(curl -s -D - ${CURL_ARGS:-} "$base$path" | tr -d '\r') || fail "$path: request failed"
  if ! head -n 1 <<<"$response" | grep -q " $status"; then
    fail "$path expected status $status, got $(head -n 1 <<<"$response")"
  fi
  if [ -n "$pattern" ] && ! grep -qE "$pattern" <<<"$response"; then
    fail "$path does not match '$pattern'"
  fi
  echo "ok   $path -> $status ${pattern:+($pattern)}"
}

docker network create "$network" >/dev/null
stub frontend
stub backend

# The proxy resolves its upstreams on startup, so it starts after the stubs.
proxy=$(docker run -d --network "$network" -p 127.0.0.1::80 \
  -e DEBUG_MODE=false -e MAX_UPLOAD_SIZE_MB=1 "$image")
containers+=("$proxy")
port=$(docker port "$proxy" 80/tcp | head -n 1 | sed 's/.*://')
base="http://127.0.0.1:$port"
for _ in $(seq 1 50); do
  if curl -s -o /dev/null "$base/"; then
    break
  fi
  sleep 0.2
done

echo "== routing"
check / 200 '^frontend uri=/ '
check /app/weekly 200 '^frontend uri=/app/weekly '
check /login 200 '^frontend uri=/login '
check /recipe-images/1 200 '^frontend uri=/recipe-images/1 '
check '/api/v1/recipes?page=2' 200 '^backend uri=/api/v1/recipes\?page=2 '
check /admin/ 200 '^backend uri=/admin/ '
check /swagger-ui/index.html 200 '^backend uri=/swagger-ui/index.html '
check /v3/api-docs/ 200 '^backend uri=/v3/api-docs/ '

echo "== debug mode off"
check /h2-console/ 401

echo "== websocket"
CURL_ARGS="-H Upgrade:websocket -H Connection:Upgrade" \
  check /api/v1/shopping/live 200 '^backend uri=/api/v1/shopping/live upgrade=websocket connection=upgrade$'
check /api/v1/shopping/live 200 '^backend uri=/api/v1/shopping/live upgrade= connection=close$'

echo "== upload limit (MAX_UPLOAD_SIZE_MB=1)"
head -c 500000 /dev/zero >"$tmp/small"
head -c 2000000 /dev/zero >"$tmp/large"
# Without the empty Expect header curl waits for a "100 Continue", which check would read as
# the status line.
CURL_ARGS="-H Expect: --data-binary @$tmp/small" check /api/v1/recipe-images 200 '^backend '
CURL_ARGS="-H Expect: --data-binary @$tmp/large" check /api/v1/recipe-images 413

echo "all checks passed"

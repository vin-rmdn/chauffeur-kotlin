#!/usr/bin/env bash
# Black-box tests for the container image.
#
#   scripts/test-image.sh <image>            e.g. scripts/test-image.sh chauffeur-kotlin:local
#   SKIP_NETWORK_SMOKE=1 scripts/test-image.sh <image>   skip the call to routes.googleapis.com
#
# Needs Docker. Uses only throwaway values generated here; no real credentials are involved.
set -euo pipefail

IMAGE="${1:?usage: $0 <image>}"
SUFFIX="$$"
NETWORK="chauffeur-test-net-${SUFFIX}"
DB_CONTAINER="chauffeur-test-db-${SUFFIX}"
WORKDIR="$(mktemp -d)"
ENV_FILE="${WORKDIR}/app.env"
DB_PASSWORD="$(openssl rand -hex 16)"
MEMORY="${MEMORY_LIMIT:-384m}" # same limit the VPS applies to app containers

failures=0

cleanup() {
  docker rm -f "${DB_CONTAINER}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/        /'; failures=$((failures + 1)); }

# run_app <docker run args...> -- <app args...>; sets $output and $status
run_app() {
  local docker_args=() app_args=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do docker_args+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  app_args=("$@")
  set +e
  output="$(docker run --rm --memory="${MEMORY}" ${docker_args[@]+"${docker_args[@]}"} "${IMAGE}" ${app_args[@]+"${app_args[@]}"} 2>&1)"
  status=$?
  set -e
}

expect_success() { # name
  if [ "${status}" -eq 0 ]; then pass "$1"; else fail "$1 (exit ${status})" "${output}"; fi
}
expect_failure_matching() { # name pattern
  if [ "${status}" -ne 0 ] && grep -qiE "$2" <<<"${output}"; then pass "$1"; else fail "$1 (exit ${status}, wanted /$2/)" "${output}"; fi
}

# ---------------------------------------------------------------- 1. static checks
uid="$(docker run --rm --entrypoint id "${IMAGE}" -u)"
if [ "${uid}" != "0" ]; then pass "runs as non-root (uid ${uid})"; else fail "runs as root"; fi

leaked="$(docker run --rm --entrypoint sh "${IMAGE}" -c \
  'find / -xdev \( -name ".env" -o -name ".env.*" -o -name "*.env" -o -name "config.toml" -o -name "id_rsa" -o -name "id_ed25519" -o -name "*.key" \) -not -path "/proc/*" -not -path "/etc/ssl/*" -not -path "/usr/lib/jvm/*" 2>/dev/null || true')"
if [ -z "${leaked}" ]; then pass "no env/config/key files inside the image"; else fail "secret-looking files in image" "${leaked}"; fi

run_app -- --help
expect_success "--help works with no configuration"

run_app -- route --help
expect_success "route --help works with no configuration"

# ---------------------------------------------------------------- 2. migrate against real Postgres
docker network create "${NETWORK}" >/dev/null
docker run -d --name "${DB_CONTAINER}" --network "${NETWORK}" \
  -e POSTGRES_USER=chauffeur -e POSTGRES_DB=chauffeur -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
  postgres:18-alpine >/dev/null

for _ in $(seq 1 60); do
  # pg_isready can be true during the init phase; require a real query over TCP
  if docker exec "${DB_CONTAINER}" psql -h 127.0.0.1 -U chauffeur -d chauffeur -tAc 'select 1' >/dev/null 2>&1; then break; fi
  sleep 1
done

umask 077
cat >"${ENV_FILE}" <<ENVEOF
GOOGLE_CLOUD__MAPS_API_KEY=invalid-key-for-ci
DATABASE__USER=chauffeur
DATABASE__PASSWORD=${DB_PASSWORD}
DATABASE__NAME=chauffeur
DATABASE__HOST=${DB_CONTAINER}
DATABASE__PORT=5432
MIGRATION__USER=chauffeur
MIGRATION__PASSWORD=${DB_PASSWORD}
MIGRATION__NAME=chauffeur
MIGRATION__HOST=${DB_CONTAINER}
MIGRATION__PORT=5432
ENVEOF

run_app --network "${NETWORK}" --env-file "${ENV_FILE}" -- migration
expect_success "migration runs against Postgres"

table="$(docker exec "${DB_CONTAINER}" psql -U chauffeur -d chauffeur -tAc "select to_regclass('public.routes')")"
if [ "${table}" = "routes" ]; then pass "routes table exists after migration"; else fail "routes table missing" "${table}"; fi

run_app --network "${NETWORK}" --env-file "${ENV_FILE}" -- migration
expect_success "migration is idempotent (second run)"

# ---------------------------------------------------------------- 3. negative cases
run_app --network "${NETWORK}" --env-file "${ENV_FILE}" -- route not-a-coordinate 1,2
expect_failure_matching "malformed coordinate is rejected" "not a valid coordinate"

run_app -- migration
expect_failure_matching "missing configuration names the missing key" "googleCloud|migration|database|GOOGLE_CLOUD|Error"

run_app --env-file "${ENV_FILE}" -e MIGRATION__HOST=127.0.0.1 -e MIGRATION__PORT=1 -- migration
expect_failure_matching "unreachable database fails cleanly" "connect|refused|Unable|failed"

# ---------------------------------------------------------------- 4. gRPC + TLS path (no secret, no billing)
if [ "${SKIP_NETWORK_SMOKE:-0}" = "1" ]; then
  echo "SKIP  gRPC/TLS smoke (SKIP_NETWORK_SMOKE=1)"
else
  ok=0
  for attempt in 1 2 3; do
    run_app --network "${NETWORK}" --env-file "${ENV_FILE}" -- route -- -6.0,106.0 -6.1,106.1
    # Google answers an invalid key with INVALID_ARGUMENT "API key not valid": proves TLS, gRPC and protobuf work.
    if [ "${status}" -ne 0 ] && grep -qiE "API key not valid|API_KEY_INVALID|INVALID_ARGUMENT" <<<"${output}"; then ok=1; break; fi
    sleep $((attempt * 3))
  done
  if [ "${ok}" -eq 1 ]; then pass "route reaches Google over TLS/gRPC (invalid key rejected as expected)"; else fail "gRPC/TLS smoke" "${output}"; fi
fi

echo
if [ "${failures}" -eq 0 ]; then echo "All image tests passed."; else echo "${failures} image test(s) failed."; exit 1; fi

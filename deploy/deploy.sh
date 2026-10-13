#!/usr/bin/env bash
# chauffeur-kotlin deploy entry point.
#
# Installed on the VPS as /usr/local/bin/chauffeur-kotlin-deploy and configured as the SSH *forced command*
# of the CI key (see deploy/authorized-key-line.sh). Whatever the client asks for arrives in
# SSH_ORIGINAL_COMMAND and is validated here against a strict grammar, so the CI key can do exactly this and
# nothing else:
#
#   deploy ghcr.io/vin-rmdn/chauffeur-kotlin@sha256:<64 hex>   (GHCR token on stdin, first line, optional)
#   status
#
# Deploy order: pull -> database up -> backup -> migrate -> smoke test -> only then move the `current` tag.
# Any failure before the last step leaves the previously deployed image untouched.
set -euo pipefail
umask 077

readonly IMAGE_REPO="ghcr.io/vin-rmdn/chauffeur-kotlin"
readonly LOCAL_IMAGE="chauffeur-kotlin"
readonly COMPOSE_PROJECT="chauffeur-kotlin"
readonly NETWORK="chauffeur-kotlin"
readonly DB_CONTAINER="chauffeur-kotlin-database"
readonly TIMER_UNIT="chauffeur-kotlin-route.timer"
readonly KEEP_BACKUPS=5
readonly APP_MEMORY="384m"

# Overridable so that tests can run against temp directories. sshd does not pass client environment variables
# (the key is `restrict`ed and PermitUserEnvironment is off), so a client cannot influence these.
CONFIG_DIR="${CHAUFFEUR_CONFIG_DIR:-/etc/chauffeur-kotlin}"
STATE_DIR="${CHAUFFEUR_STATE_DIR:-/var/lib/chauffeur-kotlin}"

DOCKER_CONFIG_TMP="" # throwaway docker config holding GHCR credentials for the duration of one deploy
cleanup() { [ -z "$DOCKER_CONFIG_TMP" ] || rm -rf "$DOCKER_CONFIG_TMP"; }
trap cleanup EXIT

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }
reject() { echo "error: rejected: $*" >&2; exit 2; }

# ----------------------------------------------------------------------------------------------- input
if [ -n "${SSH_ORIGINAL_COMMAND+x}" ]; then
  input="${SSH_ORIGINAL_COMMAND}"
else
  input="$*" # local administrator use; validated identically
fi

# Strict allow-list. Notably excludes whitespace other than one space, quotes, ; & | $ ` ( ) < > and newlines.
re='^(deploy|status)( ([A-Za-z0-9@:./-]+))?$'
[[ $input =~ $re ]] || reject "expected 'deploy <image>@sha256:<digest>' or 'status'"
command_name="${BASH_REMATCH[1]}"
image_ref="${BASH_REMATCH[3]}"

ref_re="^${IMAGE_REPO//./\\.}@sha256:[0-9a-f]{64}\$"
case "$command_name" in
  deploy)
    [ -n "$image_ref" ] || reject "deploy needs an image reference"
    [[ $image_ref =~ $ref_re ]] || reject "image must be ${IMAGE_REPO}@sha256:<64 lowercase hex>"
    ;;
  status)
    [ -z "$image_ref" ] || reject "status takes no arguments"
    ;;
esac

# ----------------------------------------------------------------------------------------------- status
cmd_status() {
  local current previous timer database
  current="$(cat "${STATE_DIR}/current" 2>/dev/null || echo none)"
  previous="$(cat "${STATE_DIR}/previous" 2>/dev/null || echo none)"
  timer="$(systemctl is-active "$TIMER_UNIT" 2>/dev/null || true)"
  database="$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || echo absent)"
  echo "current=${current}"
  echo "previous=${previous}"
  echo "timer=${timer:-unknown}"
  echo "database=${database}"
}

# ----------------------------------------------------------------------------------------------- deploy
write_state() { # name value  (atomic)
  printf '%s\n' "$2" >"${STATE_DIR}/.$1.tmp"
  mv -f "${STATE_DIR}/.$1.tmp" "${STATE_DIR}/$1"
}

backup_database() {
  local dir="${STATE_DIR}/backups" dump dumps=()
  mkdir -p "$dir"
  dump="${dir}/pre-deploy-$(date -u +%Y%m%dT%H%M%SZ).dump"

  if ! docker exec "$DB_CONTAINER" pg_dump -U chauffeur -d chauffeur -Fc >"${dump}.partial"; then
    rm -f "${dump}.partial"
    die "database backup failed; not deploying"
  fi
  mv "${dump}.partial" "$dump"

  # Timestamped names sort chronologically; keep the newest KEEP_BACKUPS.
  shopt -s nullglob
  dumps=("${dir}"/pre-deploy-*.dump)
  shopt -u nullglob
  local excess=$(( ${#dumps[@]} - KEEP_BACKUPS )) i
  for ((i = 0; i < excess; i++)); do rm -f -- "${dumps[i]}"; done
}

cmd_deploy() {
  local token="" previous_ref

  mkdir -p "$STATE_DIR"
  exec 9>"${STATE_DIR}/deploy.lock"
  flock -n 9 || die "another deploy is already running"

  [ -r "${CONFIG_DIR}/app.env" ] || die "${CONFIG_DIR}/app.env is missing or unreadable (run bootstrap.sh)"

  # The GHCR token (if any) arrives on stdin, never on the command line, and is only ever handed to
  # `docker login --password-stdin`. Credentials live in a throwaway Docker config that is deleted on exit.
  if [ ! -t 0 ]; then IFS= read -r -t 15 token || true; fi
  DOCKER_CONFIG_TMP="$(mktemp -d)"

  if [ -n "$token" ]; then
    log "logging in to ghcr.io"
    printf '%s' "$token" | DOCKER_CONFIG="$DOCKER_CONFIG_TMP" docker login ghcr.io -u github-actions --password-stdin >/dev/null
  fi
  token=""

  # A digest is immutable, so a copy that is already local (e.g. rolling back to `previous`) needs no registry access.
  if docker image inspect "$image_ref" >/dev/null 2>&1; then
    log "${image_ref} is already present locally"
  else
    log "pulling ${image_ref}"
    DOCKER_CONFIG="$DOCKER_CONFIG_TMP" docker pull --quiet "$image_ref" >/dev/null || die "pull failed"
  fi

  log "starting database"
  docker compose -p "$COMPOSE_PROJECT" -f "${CONFIG_DIR}/compose.yaml" up -d --wait database >/dev/null \
    || die "database did not become healthy"

  log "backing up database"
  backup_database

  log "running migrations"
  docker run --rm --pull=never --network "$NETWORK" --memory="$APP_MEMORY" \
    --env-file "${CONFIG_DIR}/app.env" "$image_ref" migration || die "migration failed; ${LOCAL_IMAGE}:current is unchanged"

  log "smoke testing new image"
  docker run --rm --pull=never --memory="$APP_MEMORY" "$image_ref" --help >/dev/null \
    || die "smoke test failed; ${LOCAL_IMAGE}:current is unchanged"

  # Everything passed: promote. Until this point the previous image kept serving the timer.
  previous_ref="$(cat "${STATE_DIR}/current" 2>/dev/null || true)"
  if [ -n "$previous_ref" ] && [ "$previous_ref" != "$image_ref" ]; then
    docker tag "${LOCAL_IMAGE}:current" "${LOCAL_IMAGE}:previous" 2>/dev/null || true
    write_state previous "$previous_ref"
  fi
  docker tag "$image_ref" "${LOCAL_IMAGE}:current"
  write_state current "$image_ref"

  docker image prune -f >/dev/null 2>&1 || true # untagged leftovers only; current/previous are tagged
  log "deployed ${image_ref}"
}

case "$command_name" in
  status) cmd_status ;;
  deploy) cmd_deploy ;;
esac

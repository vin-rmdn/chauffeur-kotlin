#!/usr/bin/env bash
# One-time (and safely re-runnable) setup of a VPS for chauffeur-kotlin. Run as root, from a checkout of the repo:
#
#   sudo deploy/bootstrap.sh --ci-public-key-file ci_key.pub [--enable-timer] [--no-swap]
#
# It creates the `deploy` user whose only SSH key is the CI key (restricted to deploy.sh), the config/state
# directories, the database stack, the systemd units, and the secrets files. The Google Maps API key is read
# from the terminal (hidden) or from stdin and written only to /etc/chauffeur-kotlin/app.env on this machine.
#
# Never overwrites existing secrets, so re-running is safe.
set -euo pipefail

readonly DEPLOY_USER="deploy"
readonly CONFIG_DIR="/etc/chauffeur-kotlin"
readonly STATE_DIR="/var/lib/chauffeur-kotlin"
readonly DEPLOY_BIN="/usr/local/bin/chauffeur-kotlin-deploy"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly COMPOSE_PROJECT="chauffeur-kotlin"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SELF_DIR

ci_key_file=""
enable_timer=0
make_swap=1

log() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ci-public-key-file) ci_key_file="${2:?--ci-public-key-file needs a path}"; shift 2 ;;
    --enable-timer) enable_timer=1; shift ;;
    --no-swap) make_swap=0; shift ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --------------------------------------------------------------------------------------------- preflight
[ "$(id -u)" -eq 0 ] || die "run as root"
for tool in docker systemctl openssl useradd getent install; do
  command -v "$tool" >/dev/null || die "missing required tool: $tool"
done
docker compose version >/dev/null 2>&1 || die "the docker compose plugin is required"
[ "$(uname -m)" = "x86_64" ] || warn "this VPS is $(uname -m); CI publishes amd64 images only"
getent group docker >/dev/null || die "no 'docker' group: is Docker Engine installed?"

# --------------------------------------------------------------------------------------------- deploy user
if ! getent passwd "$DEPLOY_USER" >/dev/null; then
  log "creating user ${DEPLOY_USER}"
  useradd --system --create-home --home-dir "/home/${DEPLOY_USER}" --shell /bin/bash "$DEPLOY_USER"
fi
usermod -p '*' "$DEPLOY_USER" # no password login, but not "locked" (locked accounts can refuse key auth)
usermod -aG docker "$DEPLOY_USER"

# --------------------------------------------------------------------------------------------- directories
install -d -m 0755 -o root -g root "$CONFIG_DIR"
install -d -m 0750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$STATE_DIR"

# --------------------------------------------------------------------------------------------- SSH key
ssh_dir="/home/${DEPLOY_USER}/.ssh"
authorized_keys="${ssh_dir}/authorized_keys"
# Owned by root, so the deploy user cannot rewrite its own restrictions.
install -d -m 0755 -o root -g root "$ssh_dir"
if [ -n "$ci_key_file" ]; then
  line="$("${SELF_DIR}/authorized-key-line.sh" "$ci_key_file")"
  printf '%s\n' "$line" >"${authorized_keys}.new"
  install -m 0644 -o root -g root "${authorized_keys}.new" "$authorized_keys"
  rm -f "${authorized_keys}.new"
  log "installed CI key: $(ssh-keygen -lf "$authorized_keys" 2>/dev/null || echo "see ${authorized_keys}")"
elif [ ! -s "$authorized_keys" ]; then
  die "no CI key installed yet: pass --ci-public-key-file <ci_key.pub>"
else
  log "keeping existing ${authorized_keys}"
fi

# --------------------------------------------------------------------------------------------- program files
install -m 0755 -o root -g root "${SELF_DIR}/deploy.sh" "$DEPLOY_BIN"
install -m 0644 -o root -g root "${SELF_DIR}/compose.prod.yaml" "${CONFIG_DIR}/compose.yaml"
install -m 0644 -o root -g root "${SELF_DIR}/systemd/chauffeur-kotlin-route.service" "${SYSTEMD_DIR}/chauffeur-kotlin-route.service"
install -m 0644 -o root -g root "${SELF_DIR}/systemd/chauffeur-kotlin-route.timer" "${SYSTEMD_DIR}/chauffeur-kotlin-route.timer"
systemctl daemon-reload

# --------------------------------------------------------------------------------------------- secrets
# Readable by the deploy user (group) because the docker CLI reads --env-file on the client side.
# That user is in the docker group, i.e. already root-equivalent; the file is not world-readable.
db_password_file="${CONFIG_DIR}/db-password"
app_env="${CONFIG_DIR}/app.env"

if [ ! -s "$db_password_file" ]; then
  [ ! -e "$app_env" ] || die "${app_env} exists but ${db_password_file} does not; refusing to guess a database password"
  log "generating database password"
  ( umask 077; openssl rand -hex 24 >"$db_password_file" )
fi
chown root:"$DEPLOY_USER" "$db_password_file"
chmod 0640 "$db_password_file"

if [ ! -s "$app_env" ]; then
  if [ -t 0 ]; then
    read -r -s -p "Google Maps API key (input hidden): " maps_key </dev/tty; echo
  else
    IFS= read -r maps_key || true
  fi
  [[ ${maps_key:-} =~ ^[A-Za-z0-9_-]{10,}$ ]] || die "that does not look like a Google API key (letters, digits, _ and - only)"
  db_password="$(cat "$db_password_file")"
  (
    umask 077
    cat >"${app_env}.new" <<ENVEOF
GOOGLE_CLOUD__MAPS_API_KEY=${maps_key}

DATABASE__USER=chauffeur
DATABASE__PASSWORD=${db_password}
DATABASE__NAME=chauffeur
DATABASE__HOST=database
DATABASE__PORT=5432

MIGRATION__USER=chauffeur
MIGRATION__PASSWORD=${db_password}
MIGRATION__NAME=chauffeur
MIGRATION__HOST=database
MIGRATION__PORT=5432
ENVEOF
  )
  maps_key=""
  chown root:"$DEPLOY_USER" "${app_env}.new"
  chmod 0640 "${app_env}.new"
  mv "${app_env}.new" "$app_env"
  log "wrote ${app_env}"
else
  log "keeping existing ${app_env}"
fi

if [ ! -e "${CONFIG_DIR}/route.env" ]; then
  install -m 0644 -o root -g root "${SELF_DIR}/route.env.example" "${CONFIG_DIR}/route.env"
  log "created ${CONFIG_DIR}/route.env from the example: edit ROUTE_ORIGIN / ROUTE_DESTINATION"
fi

# --------------------------------------------------------------------------------------------- database
log "starting database"
docker compose -p "$COMPOSE_PROJECT" -f "${CONFIG_DIR}/compose.yaml" up -d --wait database >/dev/null

# --------------------------------------------------------------------------------------------- swap
if [ "$make_swap" -eq 1 ] && [ -z "$(swapon --show --noheadings 2>/dev/null || true)" ] && [ ! -e /swapfile ]; then
  log "creating 2 GB swapfile"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

# --------------------------------------------------------------------------------------------- timer
if [ "$enable_timer" -eq 1 ]; then
  systemctl enable --now chauffeur-kotlin-route.timer
  log "timer enabled"
else
  log "timer NOT enabled. After editing ${CONFIG_DIR}/route.env: systemctl enable --now chauffeur-kotlin-route.timer"
fi

# --------------------------------------------------------------------------------------------- audit + next steps
if command -v sshd >/dev/null 2>&1; then
  effective="$(sshd -T 2>/dev/null || true)"
  grep -qiE '^passwordauthentication yes' <<<"$effective" && warn "sshd allows password logins; consider PasswordAuthentication no"
  grep -qiE '^permitrootlogin (yes|without-password|prohibit-password)' <<<"$effective" && warn "sshd allows root logins; consider PermitRootLogin no"
fi

echo
echo "Bootstrap complete. Next:"
echo "  1. Verify this host key fingerprint, then store 'ssh-keyscan -t ed25519 <host>' output as DEPLOY_KNOWN_HOSTS:"
if [ -r /etc/ssh/ssh_host_ed25519_key.pub ]; then echo "       $(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)"; fi
echo "  2. Add the GitHub Environment secrets (DEPLOY_SSH_KEY, DEPLOY_HOST, DEPLOY_USER, DEPLOY_KNOWN_HOSTS)."
echo "  3. Merge to main; the first deploy pulls the image and runs migrations."

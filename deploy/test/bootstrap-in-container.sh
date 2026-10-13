#!/usr/bin/env bash
# Runs INSIDE a throwaway ubuntu container (see bootstrap-test.sh). Exercises deploy/bootstrap.sh for real:
# real users, real file modes, real authorized_keys; only docker and systemctl are fakes.
set -euo pipefail

REPO=/repo
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
check() { # description command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
check_not() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi; }
# Fails unless the command exits non-zero AND its output matches the pattern, so a test cannot pass for the wrong reason.
expect_error() { # description pattern command...
  local desc="$1" pattern="$2" out; shift 2
  if out="$("$@" 2>&1)"; then fail "$desc (command succeeded)"; elif grep -qiE "$pattern" <<<"$out"; then pass "$desc"; else fail "$desc (wrong error: ${out})"; fi
}
mode() { stat -c '%a %U:%G' "$1"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq openssh-client openssl >/dev/null

groupadd docker
install -m 0755 "${REPO}/deploy/test/fake-bin/docker" /usr/local/bin/docker
install -m 0755 "${REPO}/deploy/test/fake-bin/systemctl" /usr/local/bin/systemctl
ssh-keygen -q -t ed25519 -N '' -C 'ci@test' -f /tmp/ci
ssh-keygen -q -t ecdsa -N '' -f /tmp/ecdsa

BOOTSTRAP="${REPO}/deploy/bootstrap.sh"
MAPS_KEY="AIzaTestKeyNotReal_0123456789abcdefg"

# ------------------------------------------------------------------ guards
expect_error "refuses to run as a non-root user" "run as root" runuser -u nobody -- "$BOOTSTRAP" --ci-public-key-file /tmp/ci.pub --no-swap
echo 'command="evil" ssh-ed25519 AAAAC3Nza' >/tmp/evil.pub
expect_error "refuses a non-ed25519 key" "single-line ssh-ed25519" bash -c "'$BOOTSTRAP' --ci-public-key-file /tmp/ecdsa.pub --no-swap </dev/null"
expect_error "refuses a key carrying authorized_keys options" "single-line ssh-ed25519" bash -c "'$BOOTSTRAP' --ci-public-key-file /tmp/evil.pub --no-swap </dev/null"
check_not "failed attempts left no secrets behind" test -e /etc/chauffeur-kotlin/app.env

# ------------------------------------------------------------------ first run
echo "$MAPS_KEY" | "$BOOTSTRAP" --ci-public-key-file /tmp/ci.pub --no-swap >/tmp/run1.log

check "deploy user exists" getent passwd deploy
check "deploy user is in the docker group" bash -c "id -nG deploy | tr ' ' '\n' | grep -qx docker"
check "deploy user has no usable password" bash -c "getent shadow deploy | cut -d: -f2 | grep -qx '\*'"
check "deploy program installed (root, 0755)" test "$(mode /usr/local/bin/chauffeur-kotlin-deploy)" = "755 root:root"
check "compose file installed" test -s /etc/chauffeur-kotlin/compose.yaml
check "systemd units installed" test -s /etc/systemd/system/chauffeur-kotlin-route.timer -a -s /etc/systemd/system/chauffeur-kotlin-route.service
check "state dir owned by deploy (0750)" test "$(mode /var/lib/chauffeur-kotlin)" = "750 deploy:deploy"

check "authorized_keys is root-owned 0644" test "$(mode /home/deploy/.ssh/authorized_keys)" = "644 root:root"
check ".ssh directory is root-owned" test "$(mode /home/deploy/.ssh)" = "755 root:root"
check "authorized_keys has exactly one line" test "$(wc -l </home/deploy/.ssh/authorized_keys)" -eq 1
check "key is restricted and bound to the forced command" \
  grep -q '^restrict,command="/usr/local/bin/chauffeur-kotlin-deploy" ssh-ed25519 ' /home/deploy/.ssh/authorized_keys
check "installed key is the CI key" bash -c "[ \"\$(awk '{print \$3}' /home/deploy/.ssh/authorized_keys | sed 's/^/x/')\" != x ] && grep -q \"\$(awk '{print \$2}' /tmp/ci.pub)\" /home/deploy/.ssh/authorized_keys"

check "db-password is 0640 root:deploy" test "$(mode /etc/chauffeur-kotlin/db-password)" = "640 root:deploy"
check "db-password is 48 hex characters" bash -c "grep -qE '^[0-9a-f]{48}\$' /etc/chauffeur-kotlin/db-password"
check "app.env is 0640 root:deploy" test "$(mode /etc/chauffeur-kotlin/app.env)" = "640 root:deploy"
check "app.env holds the Maps key" grep -qx "GOOGLE_CLOUD__MAPS_API_KEY=${MAPS_KEY}" /etc/chauffeur-kotlin/app.env
check "app.env database password equals db-password" bash -c "grep -qx \"DATABASE__PASSWORD=\$(cat /etc/chauffeur-kotlin/db-password)\" /etc/chauffeur-kotlin/app.env"
check "app.env points at the compose database service" grep -qx "DATABASE__HOST=database" /etc/chauffeur-kotlin/app.env
check_not "the Maps key was not echoed by bootstrap" grep -q "$MAPS_KEY" /tmp/run1.log
check "route.env created from the example" test -s /etc/chauffeur-kotlin/route.env
check "database stack was started" grep -q "starting database" /tmp/run1.log

# ------------------------------------------------------------------ re-run is a no-op for secrets
before="$(cat /etc/chauffeur-kotlin/app.env /etc/chauffeur-kotlin/db-password | sha256sum)"
"$BOOTSTRAP" --no-swap </dev/null >/tmp/run2.log
after="$(cat /etc/chauffeur-kotlin/app.env /etc/chauffeur-kotlin/db-password | sha256sum)"
check "re-run keeps existing secrets untouched" test "$before" = "$after"
check "re-run keeps the CI key without needing it again" test "$(wc -l </home/deploy/.ssh/authorized_keys)" -eq 1

# ------------------------------------------------------------------ recovery paths
rm /etc/chauffeur-kotlin/app.env
pw="$(cat /etc/chauffeur-kotlin/db-password)"
expect_error "a malformed Maps key is rejected" "does not look like a Google API key" bash -c "echo 'bad key!' | '$BOOTSTRAP' --no-swap"
check_not "no app.env after the rejected key" test -e /etc/chauffeur-kotlin/app.env
echo "$MAPS_KEY" | "$BOOTSTRAP" --no-swap >/dev/null
check "regenerated app.env reuses the existing database password" grep -qx "DATABASE__PASSWORD=${pw}" /etc/chauffeur-kotlin/app.env

rm /etc/chauffeur-kotlin/db-password
echo "GOOGLE_CLOUD__MAPS_API_KEY=x" >/etc/chauffeur-kotlin/app.env
expect_error "app.env without db-password is refused (no guessing)" "refusing to guess" bash -c "'$BOOTSTRAP' --no-swap </dev/null"

echo
if [ "$failures" -eq 0 ]; then echo "All bootstrap tests passed."; else echo "${failures} bootstrap test(s) failed."; exit 1; fi

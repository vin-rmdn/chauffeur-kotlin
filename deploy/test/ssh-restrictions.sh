#!/usr/bin/env bash
# Proves, against a real sshd, what the CI key can and cannot do. Needs Docker.
#
# The container uses the REAL authorized_keys line (deploy/authorized-key-line.sh), the REAL forced command
# (deploy/deploy.sh) and a deliberately permissive sshd_config (forwarding/agent/PTY allowed), so every
# restriction observed here comes from the key options and the forced command, not from server hardening.
set -euo pipefail
cd "$(dirname "$0")/../.."

IMAGE="chauffeur-sshd-test:$$"
CONTAINER="chauffeur-sshd-test-$$"
WORK="$(mktemp -d)"
failures=0

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; docker rmi -f "$IMAGE" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; failures=$((failures + 1)); }

REF="ghcr.io/vin-rmdn/chauffeur-kotlin@sha256:$(printf 'a%.0s' {1..64})"

ssh-keygen -q -t ed25519 -N '' -f "$WORK/ci"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/stranger"
AUTH_LINE="$(deploy/authorized-key-line.sh "$WORK/ci.pub")"

# Own build context: the repo's .dockerignore is an allow-list for the application image.
mkdir -p "$WORK/ctx"
cp deploy/deploy.sh "$WORK/ctx/deploy.sh"
cp deploy/test/fake-bin/docker deploy/test/fake-bin/systemctl "$WORK/ctx/"

docker build -q -t "$IMAGE" -f - "$WORK/ctx" >/dev/null <<'DOCKERFILE'
FROM alpine@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
RUN apk add --no-cache openssh-server bash util-linux coreutils \
 && adduser -D -s /bin/bash deploy && sed -i 's/^deploy:!:/deploy:*:/' /etc/shadow \
 && ssh-keygen -A \
 && mkdir -p /etc/chauffeur-kotlin /var/lib/chauffeur-kotlin /home/deploy/.ssh \
 && echo "DATABASE__USER=x" > /etc/chauffeur-kotlin/app.env \
 && chown -R deploy:deploy /var/lib/chauffeur-kotlin && chown deploy /etc/chauffeur-kotlin/app.env \
 && chown root:root /home/deploy/.ssh && chmod 755 /home/deploy/.ssh
COPY deploy.sh /usr/local/bin/chauffeur-kotlin-deploy
COPY docker systemctl /usr/local/bin/
RUN chmod 755 /usr/local/bin/chauffeur-kotlin-deploy /usr/local/bin/docker /usr/local/bin/systemctl
# Permissive on purpose: anything blocked in the tests below is blocked by the key, not by the server.
RUN printf '%s\n' \
  'PasswordAuthentication no' 'PubkeyAuthentication yes' 'PermitRootLogin no' 'StrictModes yes' \
  'AllowTcpForwarding yes' 'GatewayPorts no' 'AllowAgentForwarding yes' 'PermitTTY yes' 'X11Forwarding yes' \
  'PermitUserEnvironment no' > /etc/ssh/sshd_config.d/test.conf
RUN printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$AUTHORIZED_KEY_LINE" > /home/deploy/.ssh/authorized_keys' \
  'chmod 644 /home/deploy/.ssh/authorized_keys' 'exec /usr/sbin/sshd -D -e' > /entrypoint.sh && chmod 755 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

docker run -d --name "$CONTAINER" -e "AUTHORIZED_KEY_LINE=${AUTH_LINE}" -p 127.0.0.1::22 "$IMAGE" >/dev/null
PORT="$(docker port "$CONTAINER" 22/tcp | head -1 | sed 's/.*://')"

SSH_OPTS=(-p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes
          -o IdentitiesOnly=yes -o LogLevel=ERROR -o ConnectTimeout=5)
ci_ssh() { ssh "${SSH_OPTS[@]}" -i "$WORK/ci" deploy@127.0.0.1 "$@"; } # args = remote command

for _ in $(seq 1 30); do
  if ssh-keyscan -p "$PORT" 127.0.0.1 >/dev/null 2>&1; then break; fi
  sleep 0.5
done

# expect <description> <exit: zero|nonzero> <output-pattern|-> <command...>
expect() {
  local desc="$1" want="$2" pattern="$3" out rc=0; shift 3
  out="$("$@" 2>&1 </dev/null)" || rc=$?
  if [ "$want" = zero ] && [ "$rc" -ne 0 ]; then fail "$desc (exit $rc)" "$out"; return; fi
  if [ "$want" = nonzero ] && [ "$rc" -eq 0 ]; then fail "$desc (unexpectedly succeeded)" "$out"; return; fi
  if [ "$pattern" != "-" ] && ! grep -qiE "$pattern" <<<"$out"; then fail "$desc (output lacked /$pattern/)" "$out"; return; fi
  pass "$desc"
}

expect "CI key can run status" zero "current=none" ci_ssh status
expect "CI key can deploy a valid digest (token via stdin)" zero "deployed ${REF}" bash -c "echo 'ghs_token' | ssh ${SSH_OPTS[*]} -i $WORK/ci deploy@127.0.0.1 'deploy ${REF}'"
expect "status then reports the deployed digest" zero "current=${REF}" ci_ssh status

expect "arbitrary command is refused" nonzero "rejected" ci_ssh id
expect "command chaining is refused" nonzero "rejected" ci_ssh "status; id"
expect "tag instead of digest is refused" nonzero "rejected" ci_ssh "deploy ghcr.io/vin-rmdn/chauffeur-kotlin:latest"
expect "foreign repository is refused" nonzero "rejected" ci_ssh "deploy ghcr.io/evil/x@sha256:$(printf 'a%.0s' {1..64})"
expect "interactive shell request is refused" nonzero "rejected" ci_ssh
expect "scp upload is refused" nonzero "-" scp "${SSH_OPTS[@]/#-p/-P}" -i "$WORK/ci" "$WORK/ci.pub" deploy@127.0.0.1:/tmp/planted
expect "stdio/port forwarding is refused" nonzero "prohibited|failed|closed" ssh "${SSH_OPTS[@]}" -i "$WORK/ci" -W 127.0.0.1:22 deploy@127.0.0.1
expect "a different key is refused" nonzero "permission denied" ssh "${SSH_OPTS[@]}" -i "$WORK/stranger" deploy@127.0.0.1 status

# Nothing the rejected attempts asked for may have happened on the server.
if docker exec "$CONTAINER" test -e /tmp/planted; then fail "scp planted a file on the server"; else pass "no file was planted by scp"; fi

echo
if [ "$failures" -eq 0 ]; then echo "All SSH restriction tests passed."; else echo "${failures} SSH restriction test(s) failed."; exit 1; fi

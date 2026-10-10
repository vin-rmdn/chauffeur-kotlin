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

# ------------------------------------------------------------------------------------------------
# The real GitHub workflow steps (extracted from .github/workflows/deploy.yml), run against this sshd.
step_script() { # step name -> file
  python3 - "$1" ".github/workflows/deploy.yml" >"$2" <<'PY'
import sys, yaml
name, path = sys.argv[1:3]
steps = yaml.safe_load(open(path))["jobs"]["deploy"]["steps"]
print(next(s["run"] for s in steps if s["name"] == name))
PY
}
python3 -c 'import yaml' 2>/dev/null || python3 -m pip install --quiet --user pyyaml
step_script "Validate digest" "$WORK/s-validate.sh"
step_script "Prepare SSH" "$WORK/s-prepare.sh"
step_script "Deploy" "$WORK/s-deploy.sh"
step_script "Verify what is running" "$WORK/s-verify.sh"
step_script "Remove SSH material" "$WORK/s-cleanup.sh"

DIGEST_OK="sha256:$(printf 'a%.0s' {1..64})"
DIGEST_OTHER="sha256:$(printf 'b%.0s' {1..64})"
HOSTKEYS="$(ssh-keyscan -p "$PORT" -t ed25519 127.0.0.1 2>/dev/null)"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/other-host"
WRONG_HOSTKEYS="[127.0.0.1]:${PORT} $(cut -d' ' -f1,2 "$WORK/other-host.pub")"

# wf_run <script> [VAR=value ...]: runs a workflow step the way GitHub does (bash -e), with the job env.
wf_run() {
  local script="$1"; shift
  env -i PATH="$PATH" HOME="$HOME" RUNNER_TEMP="$WORK/runner" IMAGE="ghcr.io/vin-rmdn/chauffeur-kotlin" \
    DEPLOY_SSH_KEY="$(cat "$WORK/ci")" DEPLOY_HOST=127.0.0.1 DEPLOY_USER=deploy DEPLOY_PORT="$PORT" \
    DEPLOY_KNOWN_HOSTS="$HOSTKEYS" DIGEST="$DIGEST_OK" GHCR_TOKEN=ghs_workflow_token "$@" bash -e "$script"
}

mkdir -p "$WORK/runner"
expect "workflow: a malformed digest is refused before anything runs" nonzero "digest must look like" wf_run "$WORK/s-validate.sh" DIGEST=latest
expect "workflow: a mutable-tag-looking digest is refused" nonzero "digest must look like" wf_run "$WORK/s-validate.sh" "DIGEST=sha256:${DIGEST_OK:7:10}"
expect "workflow: a valid digest is accepted" zero "-" wf_run "$WORK/s-validate.sh"

expect "workflow: prepare writes key material with restrictive modes" zero "-" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-prepare.sh'"
if [ "$(stat -c %a "$WORK/runner/deploy_key" 2>/dev/null || stat -f %Lp "$WORK/runner/deploy_key")" = "600" ]; then pass "workflow: private key file is mode 600"; else fail "workflow: private key file is not mode 600"; fi

expect "workflow: deploy step succeeds over the pinned host key" zero "deployed" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-deploy.sh'"
expect "workflow: verify step passes when the VPS runs the deployed digest" zero "current=" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-verify.sh'"
expect "workflow: verify step FAILS when the VPS runs a different digest" nonzero "not running the digest" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-verify.sh' DIGEST='$DIGEST_OTHER'"

# Host key pinning: a different host key (man-in-the-middle) or no pinned key must stop the deploy cold.
bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$WRONG_HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-prepare.sh' DEPLOY_KNOWN_HOSTS='$WRONG_HOSTKEYS'" >/dev/null 2>&1
expect "workflow: a changed host key aborts the deploy" nonzero "host key verification failed|REMOTE HOST IDENTIFICATION" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS='$WRONG_HOSTKEYS'; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-deploy.sh'"
bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS=''; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-prepare.sh' DEPLOY_KNOWN_HOSTS=''" >/dev/null 2>&1
expect "workflow: no pinned host key means no connection (no trust-on-first-use)" nonzero "host key verification failed" bash -c "$(declare -f wf_run); WORK='$WORK'; PORT='$PORT'; HOSTKEYS=''; DIGEST_OK='$DIGEST_OK'; wf_run '$WORK/s-deploy.sh'"

wf_run "$WORK/s-cleanup.sh" >/dev/null 2>&1 || true
if [ ! -e "$WORK/runner/deploy_key" ] && [ ! -e "$WORK/runner/ssh_config" ] && [ ! -e "$WORK/runner/known_hosts" ]; then pass "workflow: cleanup removes key, config and known_hosts"; else fail "workflow: cleanup left files behind"; fi

# Nothing the rejected attempts asked for may have happened on the server.
if docker exec "$CONTAINER" test -e /tmp/planted; then fail "scp planted a file on the server"; else pass "no file was planted by scp"; fi

echo
if [ "$failures" -eq 0 ]; then echo "All SSH restriction tests passed."; else echo "${failures} SSH restriction test(s) failed."; exit 1; fi

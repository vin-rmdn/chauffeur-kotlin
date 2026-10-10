#!/usr/bin/env bats
# Tests for deploy/deploy.sh using fake `docker` and `systemctl` (deploy/test/fake-bin).
# Run: docker run --rm -v "$PWD:/repo" -w /repo bats/bats:1.14.0 deploy/test

REPO="ghcr.io/vin-rmdn/chauffeur-kotlin"
DIGEST="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OTHER_DIGEST="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
REF="${REPO}@sha256:${DIGEST}"
OTHER_REF="${REPO}@sha256:${OTHER_DIGEST}"
TOKEN="ghs_SuperSecretToken123"

setup() {
  DEPLOY="${BATS_TEST_DIRNAME}/../deploy.sh"
  WORK="$(mktemp -d)"
  export CHAUFFEUR_CONFIG_DIR="${WORK}/etc"
  export CHAUFFEUR_STATE_DIR="${WORK}/state"
  export FAKE_LOG="${WORK}/docker.log"
  export FAKE_STDIN_LOG="${WORK}/login-stdin.log"
  mkdir -p "$CHAUFFEUR_CONFIG_DIR" "$CHAUFFEUR_STATE_DIR"
  echo "DATABASE__USER=x" >"${CHAUFFEUR_CONFIG_DIR}/app.env"
  : >"$FAKE_LOG"; : >"$FAKE_STDIN_LOG"
  export PATH="${BATS_TEST_DIRNAME}/fake-bin:${PATH}"
  unset SSH_ORIGINAL_COMMAND FAKE_DOCKER_FAIL FAKE_TIMER_STATE FAKE_IMAGE_PRESENT
}

teardown() { rm -rf "$WORK"; }

# deploy <ssh-command> [stdin]
ssh_run() {
  local cmd="$1" stdin="${2-}"
  SSH_ORIGINAL_COMMAND="$cmd" run bash -c '"$0" <<<"$1"' "$DEPLOY" "$stdin"
}

# ----------------------------------------------------------------------------- input validation
@test "no command at all is rejected (interactive shell attempt)" {
  run bash -c "unset SSH_ORIGINAL_COMMAND; '$DEPLOY' </dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *rejected* ]]
}

@test "arbitrary commands are rejected" {
  for cmd in "id" "ls /" "bash" "scp -t /tmp/x" "sftp" "rm -rf /" "docker ps" "cat /etc/chauffeur-kotlin/app.env"; do
    ssh_run "$cmd"
    [ "$status" -eq 2 ] || { echo "accepted: $cmd"; return 1; }
  done
  [ ! -s "$FAKE_LOG" ] # nothing reached docker
}

@test "deploy without a reference is rejected" {
  ssh_run "deploy"
  [ "$status" -eq 2 ]
}

@test "deploy of an image outside the project repository is rejected" {
  ssh_run "deploy ghcr.io/evil/chauffeur-kotlin@sha256:${DIGEST}"
  [ "$status" -eq 2 ]
  ssh_run "deploy docker.io/library/alpine@sha256:${DIGEST}"
  [ "$status" -eq 2 ]
  ssh_run "deploy ${REPO}-evil@sha256:${DIGEST}"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "mutable tags and malformed digests are rejected" {
  for ref in "${REPO}:latest" "${REPO}" "${REPO}@sha256:abc" "${REPO}@sha256:${DIGEST}0" \
             "${REPO}@sha256:${DIGEST^^}" "${REPO}@sha1:${DIGEST}"; do
    ssh_run "deploy ${ref}"
    [ "$status" -eq 2 ] || { echo "accepted: $ref"; return 1; }
  done
}

@test "shell metacharacters and extra arguments are rejected" {
  for suffix in ";id" " ;id" " && id" " | id" ' $(id)' ' `id`' " extra" "  " " > /tmp/x" "'"; do
    ssh_run "deploy ${REF}${suffix}"
    [ "$status" -eq 2 ] || { echo "accepted suffix: [$suffix]"; return 1; }
  done
  [ ! -s "$FAKE_LOG" ]
}

@test "a newline cannot smuggle a second command" {
  SSH_ORIGINAL_COMMAND=$'status\nid' run "$DEPLOY" </dev/null
  [ "$status" -eq 2 ]
  SSH_ORIGINAL_COMMAND=$'deploy '"${REF}"$'\nid' run "$DEPLOY" </dev/null
  [ "$status" -eq 2 ]
}

@test "status with arguments is rejected" {
  ssh_run "status now"
  [ "$status" -eq 2 ]
}

# ----------------------------------------------------------------------------- status
@test "status reports current, previous, timer and database" {
  echo "$REF" >"${CHAUFFEUR_STATE_DIR}/current"
  ssh_run "status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"current=${REF}"* ]]
  [[ "$output" == *"previous=none"* ]]
  [[ "$output" == *"timer=active"* ]]
  [[ "$output" == *"database=healthy"* ]]
}

@test "status says none before the first deploy" {
  ssh_run "status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"current=none"* ]]
}

# ----------------------------------------------------------------------------- deploy: happy path
@test "deploy runs pull, database, backup, migration, smoke test and promotes" {
  ssh_run "deploy ${REF}" "$TOKEN"
  [ "$status" -eq 0 ]

  # ordered steps
  mapfile -t calls <"$FAKE_LOG"
  order=""
  for line in "${calls[@]}"; do
    case "$line" in
      "docker login"*) order+="login " ;;
      "docker pull"*) order+="pull " ;;
      "docker compose"*) order+="db " ;;
      "docker exec"*pg_dump*) order+="backup " ;;
      "docker run"*" migration"*) order+="migrate " ;;
      "docker run"*" --help"*) order+="smoke " ;;
      "docker tag ${REF} chauffeur-kotlin:current"*) order+="promote " ;;
    esac
  done
  [ "$order" = "login pull db backup migrate smoke promote " ]

  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$REF" ]
  [ -s "$(ls "${CHAUFFEUR_STATE_DIR}"/backups/pre-deploy-*.dump)" ]
}

@test "the migration container gets the env file and the project network" {
  ssh_run "deploy ${REF}"
  [ "$status" -eq 0 ]
  grep -qF -- "--env-file ${CHAUFFEUR_CONFIG_DIR}/app.env ${REF} migration" "$FAKE_LOG"
  grep -qF -- "--network chauffeur-kotlin" "$FAKE_LOG"
  grep -qF -- "--memory=384m" "$FAKE_LOG"
}

@test "deploying a new digest keeps the old one as previous" {
  echo "$REF" >"${CHAUFFEUR_STATE_DIR}/current"
  ssh_run "deploy ${OTHER_REF}"
  [ "$status" -eq 0 ]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$OTHER_REF" ]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/previous")" = "$REF" ]
  grep -qF "docker tag chauffeur-kotlin:current chauffeur-kotlin:previous" "$FAKE_LOG"
}

@test "redeploying the same digest does not overwrite previous" {
  echo "$REF" >"${CHAUFFEUR_STATE_DIR}/current"
  echo "$OTHER_REF" >"${CHAUFFEUR_STATE_DIR}/previous"
  ssh_run "deploy ${REF}"
  [ "$status" -eq 0 ]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/previous")" = "$OTHER_REF" ]
}

@test "an image that is already local is not pulled again (rollback to previous)" {
  FAKE_IMAGE_PRESENT=1 ssh_run "deploy ${REF}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present locally"* ]]
  ! grep -q "docker pull" "$FAKE_LOG"
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$REF" ]
}

@test "deploy works without a token (public package)" {
  ssh_run "deploy ${REF}" ""
  [ "$status" -eq 0 ]
  ! grep -q "docker login" "$FAKE_LOG"
}

# ----------------------------------------------------------------------------- secrets handling
@test "the token goes to docker login via stdin only and never appears in output, args or state" {
  ssh_run "deploy ${REF}" "$TOKEN"
  [ "$status" -eq 0 ]
  grep -qF "$TOKEN" "$FAKE_STDIN_LOG"          # login received it on stdin
  grep -qF -- "--password-stdin" "$FAKE_LOG"
  ! grep -qF "$TOKEN" "$FAKE_LOG"               # never in any docker argument
  [[ "$output" != *"$TOKEN"* ]]                 # never printed
  ! grep -rqF "$TOKEN" "$CHAUFFEUR_STATE_DIR"   # never persisted
}

@test "docker credentials live in a throwaway config directory that is removed" {
  ssh_run "deploy ${REF}" "$TOKEN"
  [ "$status" -eq 0 ]
  cfg="$(sed -n 's/.*docker login.*\[DOCKER_CONFIG=\(.*\)\]/\1/p' "$FAKE_LOG")"
  [ -n "$cfg" ]
  [ ! -e "$cfg" ]
}

@test "app.env contents are never printed" {
  echo "GOOGLE_CLOUD__MAPS_API_KEY=very-secret-key" >>"${CHAUFFEUR_CONFIG_DIR}/app.env"
  ssh_run "deploy ${REF}" "$TOKEN"
  [[ "$output" != *very-secret-key* ]]
}

# ----------------------------------------------------------------------------- failures leave current untouched
@test "pull failure aborts before touching anything" {
  echo "$OTHER_REF" >"${CHAUFFEUR_STATE_DIR}/current"
  FAKE_DOCKER_FAIL="docker pull" ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$OTHER_REF" ]
  ! grep -q "docker compose" "$FAKE_LOG"
  ! grep -q "chauffeur-kotlin:current" "$FAKE_LOG"
}

@test "backup failure aborts before migrating" {
  echo "$OTHER_REF" >"${CHAUFFEUR_STATE_DIR}/current"
  FAKE_DOCKER_FAIL="pg_dump" ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"backup failed"* ]]
  ! grep -q " migration" "$FAKE_LOG"
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$OTHER_REF" ]
  ! ls "${CHAUFFEUR_STATE_DIR}"/backups/*.partial 2>/dev/null
}

@test "migration failure keeps the previous image as current" {
  echo "$OTHER_REF" >"${CHAUFFEUR_STATE_DIR}/current"
  FAKE_DOCKER_FAIL=" migration" ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"migration failed"* ]]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$OTHER_REF" ]
  ! grep -q "docker tag" "$FAKE_LOG"
}

@test "smoke test failure keeps the previous image as current" {
  echo "$OTHER_REF" >"${CHAUFFEUR_STATE_DIR}/current"
  FAKE_DOCKER_FAIL=" --help" ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"smoke test failed"* ]]
  [ "$(cat "${CHAUFFEUR_STATE_DIR}/current")" = "$OTHER_REF" ]
  ! grep -q "docker tag" "$FAKE_LOG"
}

@test "an unhealthy database aborts the deploy" {
  FAKE_DOCKER_FAIL="docker compose" ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"healthy"* ]]
  ! grep -q " migration" "$FAKE_LOG"
}

@test "a missing app.env aborts with a pointer to bootstrap" {
  rm "${CHAUFFEUR_CONFIG_DIR}/app.env"
  ssh_run "deploy ${REF}"
  [ "$status" -ne 0 ]
  [[ "$output" == *bootstrap* ]]
  [ ! -s "$FAKE_LOG" ]
}

# ----------------------------------------------------------------------------- housekeeping
@test "only the five newest pre-deploy backups are kept" {
  mkdir -p "${CHAUFFEUR_STATE_DIR}/backups"
  for i in 1 2 3 4 5 6 7; do : >"${CHAUFFEUR_STATE_DIR}/backups/pre-deploy-2020010${i}T000000Z.dump"; done
  ssh_run "deploy ${REF}"
  [ "$status" -eq 0 ]
  [ "$(ls "${CHAUFFEUR_STATE_DIR}"/backups/pre-deploy-*.dump | wc -l)" -eq 5 ]
  [ ! -e "${CHAUFFEUR_STATE_DIR}/backups/pre-deploy-20200101T000000Z.dump" ]
  [ ! -e "${CHAUFFEUR_STATE_DIR}/backups/pre-deploy-20200102T000000Z.dump" ]
  [ ! -e "${CHAUFFEUR_STATE_DIR}/backups/pre-deploy-20200103T000000Z.dump" ]
}

@test "a concurrent deploy is refused" {
  exec 8>"${CHAUFFEUR_STATE_DIR}/deploy.lock"
  flock -n 8
  ssh_run "deploy ${REF}"
  exec 8>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"already running"* ]]
}

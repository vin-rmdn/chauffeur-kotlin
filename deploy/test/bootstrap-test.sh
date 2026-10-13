#!/usr/bin/env bash
# Host-side wrapper: runs bootstrap-in-container.sh in a disposable Ubuntu container (needs Docker).
set -euo pipefail
cd "$(dirname "$0")/../.."
docker run --rm -v "$PWD:/repo:ro" ubuntu@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 \
  bash /repo/deploy/test/bootstrap-in-container.sh

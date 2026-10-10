#!/usr/bin/env bash
# Prints the authorized_keys line for the CI deploy key.
#   deploy/authorized-key-line.sh <public key file | ->
#
# The key may run exactly one program (the forced command) and nothing else: `restrict` turns off PTY,
# agent, X11 and port forwarding, and the forced command (deploy.sh) validates whatever the client asked for.
# bootstrap.sh and the sshd integration test both use this script, so the tested line is the deployed line.
set -euo pipefail

readonly FORCED_COMMAND="${CHAUFFEUR_FORCED_COMMAND:-/usr/local/bin/chauffeur-kotlin-deploy}"

source_file="${1:?usage: $0 <public key file | ->}"
if [ "$source_file" = "-" ]; then key="$(cat)"; else key="$(cat "$source_file")"; fi

# Exactly one line, ed25519 only, no authorized_keys options smuggled in front of the key type.
re='^ssh-ed25519 AAAA[A-Za-z0-9+/]+={0,2}( [A-Za-z0-9@._-]*)?$'
[[ $key =~ $re ]] || { echo "error: expected a single-line ssh-ed25519 public key (no options)" >&2; exit 1; }

type_and_blob="${key%% *}"
rest="${key#* }"
blob="${rest%% *}"
echo "restrict,command=\"${FORCED_COMMAND}\" ${type_and_blob} ${blob} github-actions-chauffeur-kotlin"

# Deploying chauffeur-kotlin to a VPS

CI builds and tests the image, pushes it to GHCR, then runs **one** command on the VPS over SSH:

```
deploy ghcr.io/vin-rmdn/chauffeur-kotlin@sha256:<digest>
```

Nothing else is possible with the CI key. This document is the runbook.

## What lives where

| Where | What | Who can read it |
|---|---|---|
| GitHub Environment `production` | `DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_KNOWN_HOSTS` | the deploy job only |
| `/etc/chauffeur-kotlin/app.env` | Maps API key, DB credentials (`SECTION__KEY` variables) | root, group `deploy` |
| `/etc/chauffeur-kotlin/db-password` | generated Postgres password | root, group `deploy` |
| `/etc/chauffeur-kotlin/route.env` | `ROUTE_ORIGIN`, `ROUTE_DESTINATION` | everyone (not secret) |
| `/var/lib/chauffeur-kotlin/` | `current`/`previous` image refs, `backups/` (last 5 `pg_dump`s) | `deploy` |
| the image | binaries and migrations only; **no configuration or secrets** | anyone who can pull it |

The Maps API key and database password never touch GitHub, CI logs, or the repository.

## First-time setup (once, by the repository owner)

Prerequisites on the VPS: Docker Engine with the Compose plugin, `openssl`, systemd, and an SSH daemon.

1. **Create the CI key pair locally** and keep the private half out of the repo:
   ```bash
   ssh-keygen -t ed25519 -N '' -C 'chauffeur-kotlin-ci' -f ci_key
   ```
2. **Copy the repo (or just `deploy/`) to the VPS** and bootstrap, passing only the *public* key:
   ```bash
   scp -r deploy ci_key.pub root@<vps>:/root/chauffeur-setup/
   ssh root@<vps> 'cd /root/chauffeur-setup && ./deploy/bootstrap.sh --ci-public-key-file ci_key.pub'
   ```
   It prompts (hidden) for the Google Maps API key. Add `--enable-timer` once `route.env` is final, and `--no-swap`
   if the VPS already has swap.
3. **Set what to sample**: edit `/etc/chauffeur-kotlin/route.env`, then `systemctl enable --now chauffeur-kotlin-route.timer`.
4. **Pin the host key.** Bootstrap prints the VPS's ed25519 fingerprint. Verify it against your provider's console, then:
   ```bash
   ssh-keyscan -t ed25519 <vps-host> > known_hosts   # compare the fingerprint before trusting this file
   ```
5. **Create the GitHub Environment** `production` (Settings → Environments): required reviewer = you, deployment
   branches = `main` only. Add the four secrets: `DEPLOY_SSH_KEY` (contents of `ci_key`), `DEPLOY_HOST`,
   `DEPLOY_USER` (`deploy`), `DEPLOY_KNOWN_HOSTS` (contents of `known_hosts`).
6. **Delete the local private key**: `shred -u ci_key` (or `rm -P ci_key` on macOS).
7. Merge to `main`. The first deploy pulls the image, migrates the database and starts the schedule.

Also recommended: restrict the Google API key to the Routes API and to the VPS's IP, and set a budget alert.

## How a deploy works

`pull → database up → pg_dump backup → migrate → smoke test → promote`. The local tag `chauffeur-kotlin:current`
(used by the timer) only moves in the last step, so **any failure before that leaves the previous version serving**,
and the CI job fails. Migrations are forward-only: rolling back an image does not roll back the database, so keep
migrations backward compatible (add first, remove later).

Check state any time: `ssh deploy@<vps> status` prints `current=`, `previous=`, `timer=` and `database=`.

## Rollback

Re-run the workflow manually (`Actions → CI → Run workflow`) with the previous digest, or on the VPS:

```bash
sudo -u deploy chauffeur-kotlin-deploy deploy "$(cat /var/lib/chauffeur-kotlin/previous)"
```

Restoring data from a pre-deploy backup: `docker exec -i chauffeur-kotlin-database pg_restore -U chauffeur -d chauffeur --clean < /var/lib/chauffeur-kotlin/backups/pre-deploy-<timestamp>.dump`.

## Schedule: systemd timer (default) vs cron

The timer runs every 15 minutes with `Persistent=false`: each row is a sample of traffic *now*, so a catch-up run
after downtime would record the wrong moment. To change the schedule: `systemctl edit chauffeur-kotlin-route.timer`
and set `OnCalendar=` (empty first line to reset; check with `systemd-analyze calendar '<expr>'`).

Prefer cron? Disable the timer and add to root's crontab (note `flock`: cron does not prevent overlapping runs, a
systemd oneshot does):

```
*/15 * * * * . /etc/chauffeur-kotlin/route.env && flock -n /run/chauffeur-route.lock docker run --rm --pull=never --network chauffeur-kotlin --memory=384m --env-file /etc/chauffeur-kotlin/app.env chauffeur-kotlin:current route -- "$ROUTE_ORIGIN" "$ROUTE_DESTINATION" 2>&1 | logger -t chauffeur-route
```

Logs for the timer: `journalctl -u chauffeur-kotlin-route`.

## Rotating secrets

- **Maps API key**: edit `/etc/chauffeur-kotlin/app.env`. The next run picks it up; no restart.
- **CI key**: generate a new pair, `deploy/bootstrap.sh --ci-public-key-file new.pub` (replaces the key), update `DEPLOY_SSH_KEY`.
- **Database password**: `ALTER USER chauffeur PASSWORD '<new>'` in Postgres, then update both `db-password` and the two
  `*__PASSWORD` lines in `app.env`.

## Security notes and known trade-offs

- The `deploy` user is in the `docker` group, which is root-equivalent. That is why the CI key is bound to a forced
  command that accepts only `deploy <image of this repository, by sha256 digest>` and `status`. These rules are
  public on purpose; the protection is the key plus the validation, not secrecy. They are tested against a real
  `sshd` in `deploy/test/ssh-restrictions.sh`.
- `authorized_keys` is owned by root so the `deploy` user cannot loosen its own restrictions.
- The GHCR token is sent over stdin, used with `docker login --password-stdin` in a throwaway Docker config, and
  deleted at exit.
- `route` and `migration` share one env file and one database role, because the application requires every config
  section for every command. Splitting them is possible later.
- Anyone in the `docker` group can read container environment variables with `docker inspect`.
- Bootstrap does not edit `sshd_config` (lock-out risk). It warns if password or root logins are enabled.

## Tests for this directory

| Command | Covers |
|---|---|
| `docker run --rm -v "$PWD:/repo" -w /repo bats/bats:1.14.0 deploy/test` | `deploy.sh`: input validation, ordering, secret handling, failure paths |
| `deploy/test/bootstrap-test.sh` | `bootstrap.sh` in a clean Ubuntu container: users, modes, idempotency |
| `deploy/test/ssh-restrictions.sh` | what the CI key can and cannot do against a real `sshd` |

All three run in CI (`deploy-scripts` job).

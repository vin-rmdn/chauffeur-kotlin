# chauffeur-kotlin

A small Kotlin CLI that asks the [Google Maps Routes API](https://developers.google.com/maps/documentation/routes)
for a traffic-aware route and stores the result in PostgreSQL, so travel times can be tracked over the day.

```
chauffeur-kotlin migration                      # apply database migrations
chauffeur-kotlin route -- <lat,lng> <lat,lng>   # sample one route (the -- allows negative coordinates)
```

Stack: Kotlin 2.4 / JDK 25, Clikt, Hoplite, Exposed, Flyway, PostgreSQL. Shipped as a container image, deployed to a
VPS by GitHub Actions over SSH (see [`deploy/README.md`](deploy/README.md)).

## Configuration

Configuration is read from **environment variables** (`SECTION__KEY`, double underscore) and, optionally, a
`config.toml` in the working directory. Copy [`.sample.env`](.sample.env) or [`config.sample.toml`](config.sample.toml)
for local use; the real files are git-ignored. Every section is required by every command:

| Variable | Meaning |
|---|---|
| `GOOGLE_CLOUD__MAPS_API_KEY` | Google Maps API key |
| `DATABASE__{USER,PASSWORD,NAME,HOST,PORT}` | database used by `route` |
| `MIGRATION__{USER,PASSWORD,NAME,HOST,PORT,DIRECTORY}` | database and SQL directory used by `migration` |

`--help` needs no configuration. Secrets are never baked into the jar or image.

## Develop

```bash
docker compose --env-file .env up -d database   # local Postgres (see .sample.env)
./gradlew test                                  # unit tests, no Docker needed
./gradlew integrationTest                       # Postgres via Testcontainers, needs Docker
./gradlew allTests                              # both
./gradlew installDist && build/install/chauffeur-kotlin/bin/chauffeur-kotlin --help
```

## Container image

```bash
./gradlew installDist && docker build -t chauffeur-kotlin:local .
scripts/test-image.sh chauffeur-kotlin:local    # black-box tests (SKIP_NETWORK_SMOKE=1 to stay offline)
```

The image is a thin JRE layer over `installDist` output plus the SQL migrations. It contains no configuration; pass
it at run time with `docker run --env-file`.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml): lint and secret scan, unit tests, integration tests,
distribution build (these four run in parallel), deploy-tooling tests, then image build + tests + Trivy scan.
Actions are pinned to commit SHAs and tool images to digests.

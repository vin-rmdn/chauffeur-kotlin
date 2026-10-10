# Runtime image only. CI (and `./gradlew installDist` locally) builds the application first:
#   ./gradlew installDist && docker build -t chauffeur-kotlin .
FROM eclipse-temurin:25-jre-noble

ARG REVISION=unknown
LABEL org.opencontainers.image.title="chauffeur-kotlin" \
      org.opencontainers.image.source="https://github.com/vin-rmdn/chauffeur-kotlin" \
      org.opencontainers.image.revision="${REVISION}"

# Unprivileged user; the image holds no configuration or secrets (see .dockerignore).
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin chauffeur

# Permissions are set with plain numeric chmod instead of relying on how a given BuildKit version interprets
# symbolic `COPY --chmod` modes: that varies, and build output inherits whatever umask the build machine had.
# Numeric --chmod applies to files AND directories, so files get 0644 here and directories are fixed right after
# (a metadata-only change, so it does not duplicate file contents in a new layer).
COPY --chmod=0644 build/install/chauffeur-kotlin/ /opt/chauffeur-kotlin/
COPY --chmod=0644 src/main/resources/db/migration /opt/chauffeur-kotlin/migration
RUN find /opt/chauffeur-kotlin -type d -exec chmod 0755 {} + \
 && chmod 0755 /opt/chauffeur-kotlin/bin/chauffeur-kotlin

ENV MIGRATION__DIRECTORY=/opt/chauffeur-kotlin/migration

USER 10001
WORKDIR /opt/chauffeur-kotlin
ENTRYPOINT ["/opt/chauffeur-kotlin/bin/chauffeur-kotlin"]

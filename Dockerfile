# Runtime image only. CI (and `./gradlew installDist` locally) builds the application first:
#   ./gradlew installDist && docker build -t chauffeur-kotlin .
FROM eclipse-temurin:25-jre-noble

ARG REVISION=unknown
LABEL org.opencontainers.image.title="chauffeur-kotlin" \
      org.opencontainers.image.source="https://github.com/vin-rmdn/chauffeur-kotlin" \
      org.opencontainers.image.revision="${REVISION}"

# Unprivileged user; the image holds no configuration or secrets (see .dockerignore).
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin chauffeur

# Permissions are set explicitly (read-only for the runtime user, scripts executable): build output
# inherits whatever umask the build machine had, which is not reliable.
COPY --chmod=u=rwX,go=rX build/install/chauffeur-kotlin/ /opt/chauffeur-kotlin/
COPY --chmod=u=rwX,go=rX src/main/resources/db/migration /opt/chauffeur-kotlin/migration
# `X` above keeps an execute bit only if the source had one, which CI artifact transfers can lose.
# Do not depend on that: make the launcher executable explicitly.
RUN chmod 0755 /opt/chauffeur-kotlin/bin/chauffeur-kotlin

# Non-secret default. Everything else (DATABASE__*, MIGRATION__*, GOOGLE_CLOUD__*) is supplied at run time
# with `docker run --env-file`.
ENV MIGRATION__DIRECTORY=/opt/chauffeur-kotlin/migration

USER 10001
WORKDIR /opt/chauffeur-kotlin
ENTRYPOINT ["/opt/chauffeur-kotlin/bin/chauffeur-kotlin"]

# Build from the allow-listed source bundle produced by scripts/package-joycode.ps1.
FROM node:22-bookworm-slim AS web-deps
WORKDIR /web
RUN corepack enable
COPY apps/admin-web/package.json apps/admin-web/pnpm-lock.yaml apps/admin-web/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

FROM web-deps AS web-build
COPY apps/admin-web/ ./
RUN pnpm build

FROM maven:3.9.11-eclipse-temurin-21 AS api-build
WORKDIR /api
COPY services/business-api/pom.xml ./
COPY services/business-api/src/ ./src/
RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends nginx curl fonts-droid-fallback ca-certificates libatomic1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 appuser
# The Node runtime is copied from the matching Linux architecture build stage.
COPY --from=node:22-bookworm-slim /usr/local/bin/node /usr/local/bin/node
WORKDIR /app
COPY --from=api-build /api/target/*.jar /app/api.jar
COPY --from=web-build --chown=appuser:appuser /web/.next/standalone/ /app/web/
COPY --from=web-build --chown=appuser:appuser /web/.next/static/ /app/web/.next/static/
COPY --from=web-build --chown=appuser:appuser /web/public/ /app/web/public/
COPY deployment/joycode/nginx.conf /app/nginx.conf
COPY deployment/joycode/start.sh /bin/start.sh
RUN chmod 755 /bin/start.sh
ENV NODE_ENV=production PORT=3000 HOSTNAME=127.0.0.1 SERVER_PORT=8081 SERVER_ADDRESS=127.0.0.1 \
    BUSINESS_API_BASE_URL=http://127.0.0.1:8081 SPRING_PROFILES_ACTIVE=prod SECURITY_ENABLED=true \
    REPORT_PDF_FONT_PATH=/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s CMD curl --fail --silent http://127.0.0.1:8080/healthz >/dev/null || exit 1
ENTRYPOINT ["/bin/start.sh"]

FROM node:24.14.0-trixie-slim@sha256:8c8f12cedb96c3b59642cf30d713943c2b223990c9919b96a141681f62e6e292 AS base
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

FROM base AS dependencies
COPY package.json package-lock.json ./
RUN npm ci --install-strategy=nested --no-audit --no-fund

FROM base AS runtime
ENV NODE_ENV=production
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node . .
RUN mkdir -p /app/logs && chown node:node /app /app/logs
USER node
RUN npm run k135z:verify-sdk && node --check server.js
CMD ["sh", "-c", "npm run k135z:verify-sdk && exec node server.js"]

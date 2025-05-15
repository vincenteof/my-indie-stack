# === Base image with Node 20 and pnpm support ===
FROM node:20-bullseye-slim AS base

ENV NODE_ENV=production

RUN apt-get update \
 && apt-get install -y openssl sqlite3 \
 && corepack enable \
 && corepack prepare pnpm@latest --activate \
 && rm -rf /var/lib/apt/lists/*

# === Install & generate Prisma client ===
FROM base AS deps

WORKDIR /myapp

# copy manifest + lockfile
COPY package.json pnpm-lock.yaml ./

# install everything (dev + prod)
RUN pnpm install

# Prisma schema & client generation
COPY prisma ./prisma
RUN pnpm prisma generate

# === Prune dev‑deps for a minimal node_modules ===
FROM base AS production-deps

WORKDIR /myapp

# bring in manifest + lockfile (to keep prune deterministic)
COPY package.json pnpm-lock.yaml ./

# pull in built node_modules (with generated Prisma client)
COPY --from=deps /myapp/node_modules ./node_modules

# remove devDependencies
RUN pnpm prune --prod

# === Build your app (reusing full deps) ===
FROM base AS build

WORKDIR /myapp

# copy manifest + lockfile (optional but keeps consistency)
COPY package.json pnpm-lock.yaml ./

# reuse full deps (with generated Prisma client)
COPY --from=deps /myapp/node_modules ./node_modules

# copy source & build
COPY . .
RUN pnpm run build

# === Final runtime image ===
FROM base AS runtime

ENV DATABASE_URL="file:/data/sqlite.db"
ENV PORT="8080"
ENV NODE_ENV="production"

# sqlite shortcut
RUN echo "#!/bin/sh\nset -x\nsqlite3 \$DATABASE_URL" \
    > /usr/local/bin/database-cli \
 && chmod +x /usr/local/bin/database-cli

WORKDIR /myapp

# production deps only
COPY --from=production-deps /myapp/node_modules ./node_modules

# copy build output and static assets
COPY --from=build /myapp/build ./build
COPY --from=build /myapp/public ./public
COPY --from=build /myapp/package.json ./package.json
COPY --from=build /myapp/start.sh ./start.sh
COPY --from=build /myapp/prisma ./prisma

ENTRYPOINT ["./start.sh"]

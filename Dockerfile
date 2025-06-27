# Use specific version for reproducibility
FROM oven/bun:1.2.14-alpine AS base

# Install OpenSSL for Prisma for Prisma generate
RUN apk add --no-cache openssl

WORKDIR /app

# Development stage
FROM base AS development

# Copy package files for better layer caching
COPY package.json bun.lock turbo.json ./

# Copy ONLY package.json files to preserve layer cache
COPY apps/overlays/package.json ./apps/overlays/
COPY apps/server/package.json ./apps/server/
COPY packages/database/package.json packages/database/prisma ./packages/database/
COPY packages/shared/package.json ./packages/shared/
COPY packages/logger/package.json ./packages/logger/

# Install dependencies - this layer is cached if package.json files don't change
RUN bun install

# NOW copy source code - changes here won't invalidate the dependency cache
COPY apps apps
COPY packages packages

# Generate Prisma client
RUN cd packages/database && bunx prisma generate

# Expose ports
EXPOSE 7175 8080 8081 8008

# Default to development mode
ENV NODE_ENV=development

# Use exec form for proper signal handling
CMD ["bun", "run", "dev"]

# Production build stage
FROM development AS builder
ENV NODE_ENV=production

# Build the applications
RUN bun run build

# Production runtime stage
FROM base AS production
ENV NODE_ENV=production

# Install tini for proper signal handling
RUN apk add --no-cache tini

# Copy only what's needed for production
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY --from=builder /app/apps/server/dist ./apps/server/dist
COPY --from=builder /app/apps/overlays/dist ./apps/overlays/dist
COPY --from=builder /app/packages ./packages

# Expose only necessary ports
EXPOSE 7175 8080 8008

# Use tini as entrypoint
ENTRYPOINT ["/sbin/tini", "--"]

# Default to server (can be overridden in docker-compose)
CMD ["bun", "run", "apps/server/dist/index.js"]

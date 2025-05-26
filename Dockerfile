# Use specific version for reproducibility
FROM oven/bun:1.2.14-alpine

# Install OpenSSL for Prisma
RUN apk add --no-cache openssl

WORKDIR /app

# Copy package files for better layer caching
COPY package.json bun.lock ./

# Create package directories
RUN mkdir -p packages/database packages/server packages/overlays packages/shared

# Copy individual package.json files
COPY packages/database/package.json ./packages/database/
COPY packages/server/package.json ./packages/server/
COPY packages/overlays/package.json ./packages/overlays/
COPY packages/shared/package.json ./packages/shared/

# Install dependencies
RUN bun install

# Copy the rest of the application
COPY . .

# Generate Prisma client
RUN cd packages/database && bunx prisma generate

# Expose ports (documentation purposes)
EXPOSE 7175 8080 8081 8088

# Default to development mode (can be overridden in docker-compose)
ENV NODE_ENV=development

# Use exec form for proper signal handling
CMD ["bun", "run", "dev"]
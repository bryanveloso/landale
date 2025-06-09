# Use specific version for reproducibility
FROM oven/bun:1.2.14-alpine

# Install OpenSSL for Prisma
RUN apk add --no-cache openssl

WORKDIR /app

# Copy package files for better layer caching
COPY package.json bun.lock turbo.json ./
COPY apps apps
COPY packages packages

# Install dependencies
RUN bun install

# Generate Prisma client
RUN cd packages/database && bunx prisma generate

# Expose ports
EXPOSE 7175 8080 8081 8088

# Default to development mode
ENV NODE_ENV=development

# Use exec form for proper signal handling
CMD ["bun", "run", "dev"]
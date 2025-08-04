FROM oven/bun:latest AS base

WORKDIR /app

# Copy root package files first for workspace setup
COPY package.json bun.lock turbo.json ./

# Create directory structure
RUN mkdir -p packages/logger packages/shared apps/overlays

# Copy all package.json files to maintain workspace integrity
COPY packages/logger/package.json ./packages/logger/
COPY packages/shared/package.json ./packages/shared/
COPY apps/overlays/package.json ./apps/overlays/

# Install all dependencies (respects workspace)
RUN bun install

# Now copy all source files
COPY packages/logger ./packages/logger
COPY packages/shared ./packages/shared
COPY apps/overlays ./apps/overlays

# Set working directory to the overlays app
WORKDIR /app/apps/overlays

# Set WebSocket URL environment variable
ARG VITE_WEBSOCKET_URL=ws://saya:7175
ENV VITE_WEBSOCKET_URL=${VITE_WEBSOCKET_URL}

# Expose port for dev server
EXPOSE 8008

# Use Vite dev server to serve the overlays
CMD ["bun", "run", "dev", "--host", "0.0.0.0", "--port", "8008"]

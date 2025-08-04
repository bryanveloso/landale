FROM oven/bun:1.1.18-alpine

# Set working directory
WORKDIR /workspace

# Copy workspace root files first for workspace dependencies
COPY package.json bun.lock ./
COPY packages/logger ./packages/logger
COPY packages/shared ./packages/shared

# Copy overlays package files
COPY apps/overlays/package.json ./apps/overlays/

# Install dependencies from workspace root
RUN bun install --frozen-lockfile

# Now copy the overlays app source
COPY apps/overlays ./apps/overlays

# Set working directory for the app
WORKDIR /workspace/apps/overlays

# Set WebSocket URL environment variable
ARG VITE_WEBSOCKET_URL=ws://saya:7175
ENV VITE_WEBSOCKET_URL=${VITE_WEBSOCKET_URL}

# Skip build step since overlays are inherently unfinished and we're using dev server
# The dev server will compile on-the-fly

# Expose port for dev server
EXPOSE 8008

# Use Vite dev server to serve the overlays
CMD ["bun", "run", "dev", "--host", "0.0.0.0", "--port", "8008"]

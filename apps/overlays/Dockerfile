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

# Build the SolidJS application for production
# VITE_WEBSOCKET_URL will be injected at build time
WORKDIR /workspace/apps/overlays
ARG VITE_WEBSOCKET_URL=ws://saya:7175
ENV VITE_WEBSOCKET_URL=${VITE_WEBSOCKET_URL}
RUN bun run build

# Expose port for dev server
EXPOSE 8008

# Use Vite dev server to serve the overlays
CMD ["bun", "run", "dev", "--host", "0.0.0.0", "--port", "8008"]

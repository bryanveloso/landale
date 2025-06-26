FROM oven/bun:latest

WORKDIR /app

# Copy workspace files
COPY package.json bun.lockb ./
COPY apps/audio-receiver/package.json ./apps/audio-receiver/

# Install dependencies
RUN bun install --frozen-lockfile

# Copy source code
COPY packages ./packages
COPY apps/audio-receiver ./apps/audio-receiver

# Expose ports
EXPOSE 8889 8890

# Start the service
CMD ["bun", "run", "--cwd", "apps/audio-receiver", "dev"]
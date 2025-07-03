# Elixir Docker Configuration for Landale Server
# Multi-stage build for optimal production deployment

# Build stage
FROM elixir:1.16.3-otp-26 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set build ENV
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files for dependency resolution
COPY mix.exs mix.lock ./

# Install mix dependencies
RUN mix deps.get --only $MIX_ENV && \
    mix deps.compile

# Copy application source
COPY config ./config
COPY lib ./lib
COPY priv ./priv

# Compile application and create release
RUN mix compile && \
    mix release

# Production runtime stage  
FROM elixir:1.16.3-otp-26-slim AS runtime

# Install runtime dependencies (minimal since base image includes Erlang/Elixir)
RUN apt-get update && apt-get install -y \
    libncurses6 \
    openssl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create app user for security
RUN groupadd -g 1000 app && \
    useradd -u 1000 -g app -s /bin/bash -m app

# Set working directory and ownership
WORKDIR /app
RUN chown app:app /app

# Copy release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/server ./

# Create data directory for DETS files and other persistent data
RUN mkdir -p /app/data && chown app:app /app/data

# Switch to app user
USER app

# Expose ports
EXPOSE 7175 8080 8081

# Set production environment
ENV MIX_ENV=prod

# Healthcheck for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD /app/bin/server rpc ":ok" || exit 1

# Default command - start the release
CMD ["/app/bin/server", "start"]
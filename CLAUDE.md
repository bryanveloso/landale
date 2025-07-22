# CLAUDE.md - Landale Project Assistant

## Project Overview

**What**: Personal streaming overlay system for OBS - single-user setup on local network
**Architecture**: Event-driven monorepo with real-time WebSocket communication
**Network**: Runs on Tailscale VPN (not public internet) - brilliant security simplification
**Scale**: Personal project - avoid enterprise over-engineering
**Status**: Successfully stabilized after addressing memory exhaustion, race conditions, and security vulnerabilities

## Tech Stack

- **Runtime**: Bun (NOT Node.js) - use Bun APIs for everything
- **Frontend**: SolidJS with GSAP animations
- **Backend**: Elixir Phoenix with WebSocket channels
- **Database**: PostgreSQL with TimescaleDB
- **Python Services**: Phononmaser (audio), Seed (AI)
- **Build**: Turborepo for monorepo management

## Core Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Overlays  │────▶│ Phoenix      │────▶│ PostgreSQL  │
│ (SolidJS)   │     │ Server       │     │ TimescaleDB │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Phononmaser │     │     Seed     │     │   Nurvus    │
│   (Audio)   │     │     (AI)     │     │  (Manager)  │
└─────────────┘     └──────────────┘     └─────────────┘
```

### WebSocket Channels
- `dashboard:*` - Control interface updates
- `events:*` - General event stream
- `overlay:*` - Overlay animations/state
- `stream:*` - Stream status/control
- `transcription:*` - Live transcription

### Key Ports
- WebSocket Server: 7175
- TCP Server: 8080
- Phononmaser: 8889
- Health Checks: 8890

## Established Patterns (CRITICAL)

### 1. WebSocket Resilience
```python
# All Python services use shared ResilientWebSocketClient
from shared.websockets import ResilientWebSocketClient
# Features: exponential backoff, health checks, auto-reconnect
```

### 2. Memory Safety
```python
# Bounded queues prevent exhaustion
self.event_queue = asyncio.Queue(maxsize=200)  # ~20 seconds buffer
```

### 3. Event Batching
```elixir
# 50ms batching with critical event bypass
@batch_window_ms 50
@critical_events ["connection_lost", "stream_stopped", ...]
```

### 4. State Management
```elixir
# GenServer state > ETS tables (prevents race conditions)
# Use :protected access when ETS is necessary
```

### 5. Layer Orchestration
```typescript
// State machine for overlay animations
type LayerState = 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'
// Priority levels: foreground > midground > background
```

## Critical Rules

1. **Commit Messages**: ALWAYS end with a period. Format: `<description>.`
2. **Bun First**: Use Bun APIs, never Node.js equivalents
3. **Personal Scale**: Single-user system - avoid enterprise patterns
4. **Real-time Focus**: Optimize for low latency over throughput
5. **Code First**: Show working code rather than explaining
6. **Pattern Adherence**: Use established patterns from above

## Code Standards

- Frontend: SolidJS for overlays and dashboard
- Animation: GSAP with layer orchestration pattern
- Testing: Bun test (not Jest/Vitest)
- Paths: Use configured aliases (@/_, +/_, ~/\*)
- Python: Use `uv` for ALL Python commands
- Security: Change ETS tables from `:public` to `:protected`

## Architecture Patterns

### Layer Orchestration
- Three priority levels: foreground, midground, background
- State machine: hidden → entering → active → interrupted → exiting
- Higher priority layers interrupt lower ones
- Use GSAP timelines for complex sequences

### Event System
- Correlation IDs track events across services
- Phoenix PubSub for real-time broadcasting
- Circuit breakers protect external API calls (needs GenServer refactor)
- Batch event publishing when possible

### Service Configuration
- Environment variables for service URLs (avoid file path traversal)
- Health checks on separate ports
- Tailscale handles all networking security

## Commands Reference

```bash
# Development
bun dev                    # Start all workspaces
bun run dev:phononmaser    # Start audio service
bun run dev:seed           # Start AI service

# Python Dependencies
uv sync                    # Update all Python packages from root
uv cache clean             # Clean UV cache if needed

# Testing
bun test                   # Run all tests
bun test:watch             # Watch mode
bun test:coverage          # Coverage report

# Docker
docker compose up          # Run services

# Nurvus Deployment
cd apps/nurvus
mix increment_version      # ALWAYS run before release
mix release --overwrite
```

## Bun Development

**Always use Bun's built-in features:**

- `Bun.serve()` for servers (not Express)
- `Bun.test()` for testing (not Jest/Vitest)
- `Bun.file()` for file operations (not fs)
- `Bun.$` for shell commands (not execa)
- `bun:sqlite` for SQLite (not better-sqlite3)
- WebSocket is built-in (not ws package)
- `.env` loads automatically (not dotenv)

## Python Development

- **UV Workspace**: Single .venv at root shared by all Python services
- **Dependencies**: Run `uv sync` from root to update all packages
- **Run Services**: 
  - From root: `cd apps/[service] && uv run python -m src.main`
  - Or use npm scripts: `bun run dev:phononmaser` or `bun run dev:seed`
- **Editable Installs**: Changes to `packages/shared-python` reflect immediately
- Use `uv` for ALL Python commands (not pip/poetry)
- Services read config from environment variables

## Known Issues & Improvements

1. **Circuit Breaker**: Currently stateless - needs GenServer implementation
2. **Animation Hook**: Consider simplifying with GSAP master timeline
3. **Documentation**: Some guides in `docs/` are outdated - check `.claude/handoffs/implementation-roadmap.md` for latest patterns

## Development Workflow

1. **Check Patterns**: Review established patterns above before implementing
2. **Use Shared Code**: Check `packages/shared-python` for Python utilities
3. **Test Locally**: All services work on localhost for development
4. **Health Checks**: Verify services via health endpoints before debugging
5. **Version Increment**: For Nurvus changes, always increment version

## When Helping

1. **Check First**: Read the actual file/code before suggesting changes
2. **Match Style**: Follow existing patterns exactly
3. **Be Specific**: Reference exact file paths and line numbers
4. **Stay Focused**: Address only what was asked
5. **Verify Commands**: Test that suggested commands work with current setup
6. **Use Established Patterns**: Apply patterns from this document

## Don't

- Use `node`, `ts-node`, `npm`, `yarn`, or `pnpm` commands
- Import Node.js-specific packages when Bun equivalents exist
- Create enterprise patterns (service contracts, connection pooling)
- Use `:public` ETS tables (security risk)
- Forget to increment Nurvus version before builds
- Trust outdated documentation in `docs/` directory
- Over-engineer for scale - this is a personal project

## Nurvus Version Management (CRITICAL)

**⚠️ WARNING: Burrito Caching Gotcha**

Burrito caches binaries based on version numbers. If you don't increment the version, it will use a stale cached binary even after code changes.

### CalVer Strategy

Nurvus uses CalVer format: `YYYY.MM.DD{letter}` (e.g., `2025.07.17a`, `2025.07.17b`)

- **Project version**: `0.0.0` (static, satisfies Mix requirements)
- **Release version**: CalVer (what Burrito uses for caching)

### Before Every Burrito Build

```bash
cd apps/nurvus
mix increment_version  # ALWAYS run this first
mix release --overwrite
```

The Mix task automatically:
- Detects today's date
- Increments letter suffix if building multiple times per day
- Updates only the release version (keeps project at 0.0.0)

### CI Integration

CI automatically runs `mix increment_version` before builds, so every commit gets a unique version.

**Remember**: When debugging Burrito issues, ALWAYS check if you incremented the version first!

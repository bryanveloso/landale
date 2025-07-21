# CLAUDE.md - Landale Project Assistant

## Project Overview

**What**: Personal streaming overlay system for OBS - single-user setup on local network
**Architecture**: Event-driven monorepo with real-time WebSocket communication
**Network**: Runs on Tailscale VPN (not public internet) - brilliant security simplification
**Scale**: Personal project - avoid enterprise over-engineering

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

## Critical Rules

1. **Commit Messages**: ALWAYS end with a period. Format: `<description>.`
2. **Bun First**: Use Bun APIs, never Node.js equivalents
3. **Personal Scale**: Single-user system - avoid enterprise patterns
4. **Real-time Focus**: Optimize for low latency over throughput
5. **Code First**: Show working code rather than explaining

## Code Standards

- Frontend: SolidJS for overlays and dashboard
- Animation: GSAP with layer orchestration pattern
- Testing: Bun test (not Jest/Vitest)
- Paths: Use configured aliases (@/_, +/_, ~/\*)
- Python: Use `uv` for ALL Python commands

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

# Testing
bun test                   # Run all tests
bun test:watch             # Watch mode
bun test:coverage          # Coverage report

# Docker
docker compose up          # Run services
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

- Use `uv` to run ALL Python-related commands
- Services should read config from environment variables
- Avoid hardcoded file paths for configuration

## Known Issues & Improvements

1. **Circuit Breaker**: Currently stateless - needs GenServer implementation
2. **Service Config**: Python services use brittle file traversal - migrate to env vars
3. **Animation Hook**: Consider simplifying with GSAP master timeline

## When Helping

1. **Check First**: Read the actual file/code before suggesting changes
2. **Match Style**: Follow existing patterns exactly
3. **Be Specific**: Reference exact file paths and line numbers
4. **Stay Focused**: Address only what was asked
5. **Verify Commands**: Test that suggested commands work with the current setup

## Don't

- Use `node`, `ts-node`, `npm`, `yarn`, or `pnpm` commands
- Import `express`, `ws`, `dotenv`, `execa`, `better-sqlite3`, `ioredis`, `pg`, or `postgres.js`
- Use `webpack`, `esbuild`, `jest`, or `vitest`
- Import from `node:fs` when `Bun.file` would work
- Create separate bundler configs - Bun handles bundling automatically
- Add test runners - use `bun test`
- Forget the period in commit messages
- Make assumptions without checking actual files first
- Over-engineer for scale - this is a personal project

## Nurvus Version Management (CRITICAL)

**⚠️ WARNING: Burrito Caching Gotcha**

Burrito caches binaries based on version numbers. If you don't increment the version, it will use a stale cached binary even after code changes. This cost us 6 hours of debugging.

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

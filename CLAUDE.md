# CLAUDE.md - Landale Project Assistant

## Project Overview

**What**: Personal streaming overlay system for OBS - single-user setup on local network
**Purpose**: Create sophisticated, animated streaming overlays that respond to audio, chat, and viewer interactions in real-time
**Architecture**: Event-driven monorepo with real-time WebSocket communication
**Network**: Runs on Tailscale VPN (not public internet) - brilliant security simplification
**Scale**: Personal project - avoid enterprise over-engineering while maintaining video production-grade patterns
**Stability**: Production-ready with resilient patterns for memory management, state handling, and security

### Key Features

- Real-time WebSocket-based event distribution across multiple services
- Multi-layered animation system with priority-based interruption handling
- Live audio transcription and processing
- AI-powered stream context analysis and correlation
- Distributed multi-machine architecture (Zelan, Demi, Saya, Alys)
- Comprehensive health monitoring and resilience patterns

## Tech Stack

### Core Technologies

- **Runtime**: Bun (NOT Node.js) - use Bun APIs for everything
- **Frontend**: SolidJS with GSAP animations
- **Backend**: Elixir Phoenix with WebSocket channels
- **Database**: PostgreSQL with TimescaleDB extension
- **Python Services**: Phononmaser (audio), Seed (AI)
- **Build**: Turborepo for monorepo management
- **Process Management**: Custom Nurvus binary (Elixir-based)
- **Container**: Docker Compose
- **UI Framework**: Tauri for dashboard app

### Key Dependencies

- **Frontend**: SolidJS, GSAP, Phoenix JS client, Tailwind CSS
- **Backend**: Phoenix Framework, Ecto, Oban, Phoenix PubSub
- **Python**: aiohttp, websockets, numpy, shared utilities
- **Monitoring**: Structured JSON logging
- **Testing**: Bun test, ExUnit (Elixir)

## Core Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Overlays.   │────▶│ Phoenix      │────▶│ PostgreSQL  │
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
- Phononmaser: 8889 (WebSocket), 8890 (Health Check)
- Seed: 8891 (Health Check)
- PostgreSQL: 5433 (custom port)

## Established Patterns (CRITICAL)

### 1. WebSocket Resilience

```python
# All Python services use shared BaseWebSocketClient
from shared.websockets import BaseWebSocketClient
# Features: connection state management, event handling, reconnection support
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
# EXCEPTION: correlation_id_pool uses :public for atomic operations (documented)
```

### 5. Layer Orchestration

```typescript
// State machine for overlay animations
type LayerState = 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'
// Priority levels: foreground > midground > background
// GSAP contexts properly managed - no memory leaks
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
- Circuit breakers protect external API calls (CircuitBreakerServer implemented)
- Batch event publishing when possible
- All Phoenix channels have catch-all handlers for safety

### Service Configuration

- Environment variables for service URLs (avoid file path traversal)
- Health checks on separate ports
- Tailscale handles all networking security

## Refactoring Protocol (CRITICAL)

**Before ANY refactoring that renames, moves, or removes code:**

1. **Document intent**: "Renaming `old_thing` to `new_thing` because..."
2. **Search and document ALL references**:
   ```bash
   rg 'old_function_name' --type elixir
   rg 'old_config_key' --type elixir
   rg ':old_field' --type elixir
   ```
3. **Paste full results** (files + line numbers) into refactor.md
4. **Check off each reference** as you update it
5. **Only commit when refactor.md is empty**

**Why this matters**: During recent OAuth refactoring, we encountered runtime errors because some references were updated while others weren't. This protocol ensures systematic reference handling.

## Issue Analysis Framework (IAI)

**When documenting any code issues, bugs, or technical challenges, use this structure:**

### 1. Incident (Factual & Neutral)

- **What happened**: Specific, observable behavior
- **When**: Timeline if relevant
- **Impact**: Quantifiable effects
- **Avoid**: Dramatic language, blame, emotional framing

### 2. Analysis (Technical Causality)

- **Root cause**: Technical explanation of why it occurred
- **Contributing factors**: System conditions that enabled the issue
- **Evidence**: Code references, logs, reproduction steps
- **Avoid**: "We messed up", "huge oversight", personal fault

### 3. Improvement (Systematic & Actionable)

- **Immediate fix**: What resolved the issue
- **Preventive measures**: System changes to prevent recurrence
- **Process improvements**: Workflow updates
- **Verification**: How to confirm the fix works

**Example Template:**

```markdown
## Engineering Analysis: [Brief Description]

**Incident**: During X deployment, we observed Y behavior resulting in Z impact.

**Analysis**: Root cause was [technical explanation]. This occurred because [system conditions].

**Improvements**:

- Fixed by [immediate resolution]
- Prevented future occurrences with [systematic change]
- Updated process to [workflow improvement]
```

**Remember**: Technical challenges are normal engineering work. Frame them as learning opportunities and process improvements, not crises.

## Current State (2025-08-07)

### Infrastructure Achievements

- **WebSocket Tracking**: Connection lifecycle managed via Phoenix.Tracker (WebSocketTracker)
- **Event Handler Safety**: All Phoenix channels have catch-all handlers
- **Debug Interface**: Full `window.debug` implementation with query params
- **Circuit Breakers**: Consolidated to CircuitBreakerServer pattern
- **Batch Request Handling**: OBS operations optimized
- **Test Infrastructure**: Strong Elixir (92 files) and TypeScript (142 files) coverage
- **Concurrency Controls**: Task streams properly bounded
- **ETS Security**: Using :protected tables (except correlation_id_pool which uses :public for atomic operations)
- **Python WebSocket**: BaseWebSocketClient provides connection resilience

### What's Working Well

- WebSocket resilience patterns prevent connection issues
- Telemetry collection provides real-time insights
- Debug interface enables rapid troubleshooting
- Health check standards ensure service reliability
- Pre-commit validation catches issues early
- Test infrastructure solid for Elixir (92 test files) and TypeScript (142 test files)

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

# WebSocket Resilience Testing
# Test automatic reconnection:
cd apps/server && mix phx.server  # Start Phoenix (Ctrl+C to stop)
# In another terminal:
cd apps/seed && uv run python -m src.main
# Check health endpoint:
curl http://localhost:8891/health
curl http://localhost:8891/status
# For phononmaser:
curl http://localhost:8890/health
# Services should reconnect within 3 seconds after Phoenix restart
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
  - Or use bun scripts: `bun run dev:phononmaser` or `bun run dev:seed`
- **Editable Installs**: Changes to `packages/shared-python` reflect immediately
- Use `uv` for ALL Python commands (not pip/poetry)
- Services read config from environment variables
- **WebSocket Pattern**: Services extend `BaseWebSocketClient` from `shared.websockets`
  - Provides connection state management and event handling
  - Implement `on_connected()`, `on_disconnected()`, `on_message()` handlers
  - Automatic reconnection built into base class

## Known Limitations

1. **TypeScript Test Coverage**: Only 2 test files exist (~1% coverage) - Critical gap
   - Only 1 real test (layer orchestrator) and 1 placeholder
   - Frontend essentially untested despite 143 test files claimed in old docs
2. **Python Test Coverage**: 10 test files exist (~15% coverage, needs 50-65% target)
   - phononmaser has 6 test files
   - seed has 3 test files
   - shared-python has 1 test file
   - Need comprehensive test suite for WebSocket resilience patterns
3. **Telemetry Dashboard**: Basic implementation exists but could be enhanced
   - Metrics are collected in `apps/server/lib/server_web/channels/telemetry_channel.ex`
   - Data is broadcast via `dashboard:telemetry` Phoenix channel every 2 seconds
   - Basic dashboard available at `/telemetry` route in dashboard app (shows service status)
   - Could be enhanced with more detailed metrics visualization
4. **Documentation**: Some guides in `handbook/` are from July 2025 and may not reflect August improvements
5. **Python Template**: Resilience patterns exist but no standardized template

## Architecture Assessment Summary

### Strengths

- **Appropriate Scale**: Correctly sized for personal use without over-engineering
- **Resilience Patterns**: Professional-grade WebSocket handling, circuit breakers, memory protection
- **Clean Separation**: Clear service boundaries with defined responsibilities
- **Developer Experience**: Comprehensive documentation, refactoring protocols, configuration management

### Next Priorities

1. **Build Telemetry Dashboard**: Visualize the metrics already being collected
2. **Document Test Patterns**: Capture MockWebSocketConnection implementation
3. **Create Python Service Template**: Standardize resilience patterns
4. **Update Documentation**: Remove outdated references, document what's real

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

- Use `node`, `ts-node`, `npm`, `yarn`, or `pnpm` commands (use `bun` instead)
- Import Node.js-specific packages when Bun equivalents exist
- Create enterprise patterns (service contracts, connection pooling)
- Forget to increment Nurvus version before builds
- Over-engineer for scale - this is a personal project
- **Add authentication to services running on Tailscale** - the network IS the security

## Authentication Strategy (CRITICAL)

### Core Principle: Tailscale Provides Security

For services running exclusively within our private Tailscale network, the network itself is the security boundary. Adding application-level authentication is overengineering.

**What NOT to implement:**

- Bearer token authentication for internal APIs
- JWT validation middleware
- WebSocket token verification
- Custom session management
- OAuth flows for internal services

**What TO implement:**

- Rate limiting (100 req/min) for DoS protection
- Input validation to prevent injection attacks
- CORS configuration for browser security
- Tailscale ACLs for network access control

**Exceptions (when auth IS needed):**

- Services exposed to public internet
- Multi-user features with different access levels
- Compliance/auditing requiring user-level tracking

**Remember:** This is a personal project on a private network. Keep it simple.

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

## Directory Structure

```
landale/
├── apps/                      # Main applications
│   ├── server/               # Phoenix WebSocket hub (Elixir) - Central event distribution
│   ├── overlays/             # SolidJS overlay UI - OBS browser sources
│   ├── dashboard/            # Control interface (Tauri + SolidJS) - Stream management
│   ├── phononmaser/          # Audio processing service (Python) - Transcription
│   ├── seed/                 # AI/LLM integration (Python) - Context analysis
│   └── nurvus/               # Process manager (Elixir) - Service orchestration
├── packages/                  # Shared code
│   ├── shared/               # TypeScript types/utilities
│   ├── shared-python/        # Python utilities (WebSocket client, config)
│   └── shared-elixir/        # Elixir shared code
├── handbook/                  # Architecture documentation and patterns
├── scripts/                   # Utility scripts for development
└── .claude/                   # Claude-specific handoffs and docs
```

## Integration Points

### Internal Services

- **Phoenix WebSocket Hub**: Central event broker (port 7175)
- **Health Check API**: Service monitoring endpoints (port 8890)
- **PostgreSQL + TimescaleDB**: Time-series event storage (port 5433)
- **Inter-service Communication**: All via Phoenix PubSub channels

### External Integrations

- **OBS WebSocket**: Stream control and scene management
- **AI/LLM APIs**: Context generation via Seed service
- **Audio Pipeline**: Real-time transcription processing

### Multi-Machine Architecture

- **Zelan**: Primary development machine
- **Demi**: Production streaming machine
- **Saya**: Secondary services host
- **Alys**: Additional compute resources
- All connected via Tailscale VPN mesh network

## Technical Architecture Notes

### Key Design Decisions

- **Memory Protection**: Bounded queues (200 item limit) prevent exhaustion
- **State Management**: GenServer state preferred over ETS tables to prevent race conditions
- **Security**: Tailscale network provides authentication; app focuses on rate limiting & validation
- **Connection Resilience**: WebSocket clients implement exponential backoff and auto-reconnect

### Architectural Status

1. **Circuit Breaker**: Properly implemented as CircuitBreakerServer
2. **Event Handlers**: All channels protected with catch-all handlers
3. **Debug Interface**: Fully functional with `window.debug`
4. **Concurrency**: Properly bounded with max_concurrency controls
5. **Test Infrastructure**: MockWebSocketConnection enables proper testing

### Extension Points

- **Observability**: Architecture supports OpenTelemetry integration
- **State Persistence**: Could add persistent state across restarts if needed
- **Event Sourcing**: Current design allows future event sourcing implementation
- **Performance Metrics**: Can add animation frame rate and latency monitoring

---

## Zen MCP Integration

### Overview

Landale integrates with Zen MCP (Model Context Protocol) for enhanced multi-model AI assistance. This enables:

- Comprehensive code analysis across multiple AI models
- Persistent conversation memory
- Structured debugging and refactoring workflows
- Context-aware development assistance

### Available Zen Commands

```bash
# Analysis and Investigation
/zen:analyze      # Architecture analysis with chosen model
/zen:debug        # Debug complex issues with systematic approach
/zen:refactor     # Identify refactoring opportunities
/zen:thinkdeep    # Deep reasoning for complex problems

# Planning and Documentation
/zen:planner      # Create structured development plans
/zen:consensus    # Get multi-model perspectives on decisions
/zen:codereview   # Comprehensive code review workflow
/zen:testgen      # Generate comprehensive test suites

# Specialized Workflows
/zen:precommit    # Pre-commit validation across repositories
/zen:secaudit     # Security audit with OWASP analysis
/zen:docgen       # Generate/update code documentation
/zen:tracer       # Trace execution flow and dependencies

# General Chat
/zen:chat         # Collaborative thinking with any model
/zen:challenge    # Critical analysis of your assumptions
/zen:listmodels   # See available AI models
```

### Multi-Model Strategy

Choose models based on task requirements:

#### For Landale Development

**Architecture & Design** (Use Gemini Pro or Claude)

- System design decisions
- Architecture analysis
- Performance optimization strategies
- Integration planning

**Debugging & Investigation** (Use local Llama for privacy)

- Runtime issue analysis
- Memory leak detection
- Race condition investigation
- Keep code analysis private

**Refactoring & Code Quality** (Use Gemini Flash)

- Quick refactoring suggestions
- Code smell detection
- Pattern improvements
- Fast iteration

**Documentation & Planning** (Use Claude or Gemini Pro)

- Comprehensive documentation
- Development roadmaps
- Technical specifications
- API documentation

**Security Analysis** (Use multiple models)

- Get perspectives from different models
- Cross-validate security findings
- Comprehensive vulnerability assessment

### Development Workflow with Zen

#### 1. Starting New Features

```bash
# Get architecture perspective
/zen:analyze Review how [feature] fits into Landale architecture

# Create implementation plan
/zen:planner Create step-by-step plan for implementing [feature]

# Check integration points
/zen:chat How should [feature] integrate with existing Phoenix channels?
```

#### 2. Debugging Issues

```bash
# Private code analysis (uses local model)
/zen:debug Investigate why [component] is failing

# Trace execution flow
/zen:tracer Trace how events flow from [source] to [destination]

# Get fresh perspective
/zen:challenge My assumption is [X]. What am I missing?
```

#### 3. Code Review Process

```bash
# Before committing
/zen:precommit Check my changes for issues

# Comprehensive review
/zen:codereview Review [component] for quality and security

# Security check
/zen:secaudit Quick security check of authentication flow
```

#### 4. Improving Code Quality

```bash
# Find refactoring opportunities
/zen:refactor Identify improvements in [service]

# Generate tests
/zen:testgen Create tests for [component] critical paths

# Update documentation
/zen:docgen Update docs for [module]
```

### Context Management

#### When to Use /clear

- Starting completely new task
- Context getting confused
- Need fresh perspective
- After major refactoring

#### When to Use Zen Memory

- Building on previous analysis
- Continuing development plan
- Iterating on same feature
- Maintaining conversation thread

#### Continuation IDs

```python
# Continue previous analysis
continuation_id: "your-previous-id"

# This maintains context across:
- Different Zen tools
- Multiple work sessions
- Team handoffs
```

### Best Practices

1. **Start with Analysis**: Use `/zen:analyze` before major changes
2. **Plan Before Coding**: Use `/zen:planner` for complex features
3. **Debug Systematically**: Use `/zen:debug` for tough bugs
4. **Review Regularly**: Use `/zen:codereview` before merging
5. **Document Reality**: Use `/zen:docgen` to keep docs current

### Integration Examples

#### Example 1: Adding New Service

```bash
# 1. Analyze architecture fit
/zen:analyze How should a metrics collection service integrate with Landale?

# 2. Plan implementation
/zen:planner Create plan for metrics service with Phoenix integration

# 3. Generate scaffolding
/zen:chat Show WebSocket client template for new Python service

# 4. Create tests
/zen:testgen Generate tests for metrics event handling
```

#### Example 2: Performance Investigation

```bash
# 1. Debug performance issue
/zen:debug Memory usage growing in overlay animations

# 2. Trace problem flow
/zen:tracer Trace GSAP animation lifecycle in layer orchestrator

# 3. Get refactoring suggestions
/zen:refactor Optimize memory usage in animation system

# 4. Validate fix
/zen:precommit Verify memory leak fixes before commit
```

### Model Selection Guide

| Task Type      | Recommended Model | Why                  |
| -------------- | ----------------- | -------------------- |
| Architecture   | Gemini Pro        | Deep reasoning       |
| Quick Analysis | Gemini Flash      | Fast iteration       |
| Private Debug  | Local Llama       | Code stays local     |
| Documentation  | Claude/Gemini Pro | Comprehensive output |
| Security       | Multiple Models   | Cross-validation     |
| Planning       | Gemini Pro        | Structured thinking  |

### Tips for Effective Use

1. **Be Specific**: "Debug WebSocket reconnection" > "Debug network issues"
2. **Provide Context**: Include file paths, error messages, logs
3. **Use Continuation**: Build on previous analysis with continuation_id
4. **Choose Right Model**: Match model capabilities to task needs
5. **Save Important Results**: Handoff files preserve analysis

### Common Landale + Zen Patterns

```bash
# When starting a coding session
/zen:chat What's the best approach for [today's task]?
/zen:analyze Quick review of [component] before diving in

# When stuck or frustrated
/zen:debug Why is [feature] not working as expected?
/zen:challenge I think [X] but it's not working

# Before pushing changes
/zen:precommit Validate changes before pushing
/zen:codereview Quick review of changes

# When considering big changes
/zen:consensus Should we implement [architectural change]?
/zen:planner Break down [complex feature] into manageable steps
```

### TO MIGRATE PRODUCTION

`docker exec landale-server-1 /app/bin/server eval "Server.Release.migrate()"`

Remember: Zen MCP enhances Landale development by providing structured, multi-model analysis while maintaining our personal-scale, pragmatic approach.

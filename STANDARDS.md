# Landale Development Standards

> Production-grade patterns at personal scale
> Unified standards from architecture, code quality, and security analysis

## Core Principles

1. **Security is Non-Negotiable** - All security requirements are mandatory from day one
2. **Personal Scale Filter** - Every decision must be appropriate for a personal streaming overlay
3. **Metrics as Signals, Not Gates** - Code quality metrics guide development but don't block progress

## Quick Reference

### 🔴 Critical Security Rules

- **NEVER** use wildcard CORS origins
- **NO AUTHENTICATION** for Tailscale-protected services (network IS the security)
- **ALWAYS** use parameterized database queries
- **NEVER** use `shell=True` in Python subprocess
- **NEVER** log or commit secrets/tokens
- **ALWAYS** encrypt stored tokens (when tokens exist for external services)

### 🚀 Development Priorities

1. Security implementation (Day 1)
2. Test infrastructure setup (Week 1)
3. Service decomposition (Week 2)
4. Documentation and monitoring (Week 3-4)

## Architectural Standards

### Service Architecture (Right-Sized)

- **Pattern**: Elixir umbrella application (NOT microservices)
- **Boundaries**: Clear module separation within monolith initially
- **Communication**: Phoenix Channels for all real-time events
- **State Management**: GenServer > ETS > Database

### Resilience Patterns

```elixir
# Start Simple
- Basic retry with exponential backoff
- Bounded message queues (200 items max)
- Structured JSON logging

# Add When Needed (not immediately)
- Circuit breakers (after recurring failures)
- Advanced observability (when debugging requires it)
- Complex retry strategies
```

## Code Quality Standards

### File Size Limits (Guidelines, Not Blockers)

| Language   | Soft Limit | Hard Limit | Action              |
| ---------- | ---------- | ---------- | ------------------- |
| Elixir     | 400 lines  | 500 lines  | Refactor discussion |
| TypeScript | 300 lines  | 400 lines  | Refactor discussion |
| Python     | 300 lines  | 400 lines  | Refactor discussion |

### Complexity Metrics

- **Cyclomatic Complexity**: Max 10 (warning at 8)
- **Function Length**: Max 50 lines (warning at 30)
- **Nesting Depth**: Max 4 levels

### Test Coverage Targets (Adjusted for Personal Scale)

| Language   | Minimum | Target | Focus              |
| ---------- | ------- | ------ | ------------------ |
| Elixir     | 60%     | 65%    | Business logic     |
| TypeScript | 50%     | 60%    | Critical paths     |
| Python     | 50%     | 65%    | Service interfaces |

## Language Standards

### Elixir/Phoenix

#### Code Style

```elixir
# ✅ GOOD: Pattern matching over conditionals
case result do
  {:ok, value} -> process(value)
  {:error, reason} -> handle_error(reason)
end

# ✅ GOOD: GenServer for stateful components
defmodule Server.StreamManager do
  use GenServer
  # Clear boundaries and single responsibility
end

# ❌ BAD: Public ETS tables (SECURITY RISK)
:ets.new(:my_table, [:named_table, :public])  # NEVER
# ✅ GOOD: Protected ETS when needed
:ets.new(:my_table, [:named_table, :protected])
```

#### Requirements

- Run `mix format` before commits
- Pass `mix credo` (not necessarily --strict)
- GenServer state preferred over ETS
- When ETS needed, use `:protected` access
- Document service boundaries in `@moduledoc`

### Python Services

#### Code Style

```python
# ✅ GOOD: Always use shared base class
from shared.websockets import BaseWebSocketClient

class MyService(BaseWebSocketClient):
    def __init__(self):
        super().__init__(url)
        # Bounded queue prevents memory exhaustion
        self.event_queue = asyncio.Queue(maxsize=200)

# ❌ BAD: Shell execution (SECURITY RISK)
subprocess.run(cmd, shell=True)  # NEVER
# ✅ GOOD: List arguments, no shell
subprocess.run(["cmd", "arg1"], shell=False)
```

#### Requirements

- Format with Black: `black apps/`
- Lint with Ruff: `ruff check apps/`
- Use UV package manager exclusively
- Type hints for public functions
- Always extend BaseWebSocketClient
- Never use shell=True in subprocess

### TypeScript/SolidJS

#### Code Style

```typescript
// ✅ GOOD: Proper GSAP cleanup
createEffect(() => {
  const timeline = gsap.timeline()
  onCleanup(() => {
    timeline.kill()
    timeline.clear()
  })
})

// ✅ GOOD: Bounded collections
const MAX_QUEUE_SIZE = 1000
if (queue.length >= MAX_QUEUE_SIZE) {
  queue.shift() // Remove oldest
}

// ❌ BAD: Memory leak
gsap.to(element, { x: 100 }) // No cleanup!
```

#### Requirements

- Format with Prettier
- Pass ESLint checks
- Use Bun runtime exclusively (NEVER Node.js)
- Mandatory GSAP cleanup in all animations
- Type all component props
- Bounded message queues

## Security Standards (MANDATORY)

### API Authentication

```elixir
# REQUIRED on ALL API endpoints
pipeline :api do
  plug :accepts, ["json"]
  plug ServerWeb.Plugs.APIAuth  # NO EXCEPTIONS
end

# ONLY health/ready may be public
scope "/" do
  get "/health", ServerWeb.HealthController, :check
  get "/ready", ServerWeb.HealthController, :ready
end
```

### CORS Configuration

```elixir
# NEVER use wildcards
plug Corsica,
  origins: System.get_env("PHOENIX_CORS_ORIGIN") |> String.split(","),
  allow_headers: ["content-type", "authorization"],
  max_age: 86400
```

### Input Validation

```elixir
# All user inputs MUST be validated
def process_input(input) when is_binary(input) do
  cond do
    String.length(input) > 100 -> {:error, :too_long}
    String.match?(input, ~r/[<>"']/) -> {:error, :invalid_chars}
    true -> {:ok, sanitize(input)}
  end
end
```

### Secret Management

- Environment variables for ALL secrets
- Encrypted storage for tokens (use Cloak)
- No hardcoded credentials (enforced by pre-commit)
- Token rotation capability required

### Rate Limiting (Personal Scale)

```elixir
rule "general API" do
  throttle(conn.remote_ip, period: 60_000, limit: 100)
end

rule "auth endpoints" do
  throttle(conn.remote_ip, period: 60_000, limit: 10)
end
```

### Security Headers

```elixir
plug Plug.SecureHeaders,
  hsts: true,
  x_frame_options: "DENY",
  x_content_type_options: "nosniff",
  x_xss_protection: "1; mode=block"
```

## Memory Management (Required Patterns)

### Frontend

```typescript
// Mandatory cleanup pattern
private cleanupTimeline(timeline: gsap.core.Timeline) {
  try {
    timeline.kill();
    timeline.clear();
    this.activeTimelines.delete(timeline);
  } catch (error) {
    console.error('Cleanup failed:', error);
    this.activeTimelines.delete(timeline);
  } finally {
    timeline = null;
  }
}
```

### Backend

```elixir
# Bounded GenServer state
def handle_cast({:add_item, item}, state) when length(state.items) < 1000 do
  {:noreply, %{state | items: [item | state.items]}}
end
```

### Python

```python
# Bounded queues (200 items = ~20 seconds buffer)
self.event_queue = asyncio.Queue(maxsize=200)
```

## Observability Standards

### Structured Logging

```elixir
# Required for all events
Logger.info("Event processed",
  event_type: type,
  correlation_id: id,
  duration_ms: duration
)
```

### Health Checks

- All services expose `/health` endpoint
- Include service-specific metrics
- Return structured JSON response

### Telemetry (Start Simple)

- Use Phoenix telemetry for basic metrics
- Start with counters and gauges
- Add histograms only when debugging requires it

### Test Patterns

#### WebSocket Mocking

```elixir
# Use MockWebSocketConnection
defmodule MyTest do
  use Server.MockWebSocketConnection

  test "handles connection" do
    assert_websocket_connected()
    assert_websocket_message(%{type: "event"})
  end
end
```

#### Service Testing

```python
# Use shared test utilities
from shared.testing import MockWebSocketClient

async def test_service():
    client = MockWebSocketClient()
    service = MyService(client)
    await service.start()
    assert service.healthy()
```

## Security Standards

### Authentication Strategy for Tailscale Networks

**CRITICAL: Services on Tailscale DO NOT need application-level authentication**

#### What NOT to Add (Overengineering)

- Bearer token authentication for internal APIs
- JWT validation middleware
- WebSocket token verification
- Session management for internal services
- OAuth flows for Tailscale-protected endpoints

#### What TO Add (Appropriate Security)

- Rate limiting (100 req/min per IP) for DoS protection
- Input validation to prevent injection attacks
- CORS configuration for browser security
- Tailscale ACLs for network access control

#### When Authentication IS Required

- Services exposed to public internet
- Multi-user features with access levels
- Compliance requiring user-level auditing
- External API integrations (Twitch, Discord, etc.)

### Data Protection

```elixir
# ✅ GOOD: Parameterized query
Repo.all(from u in User, where: u.id == ^user_id)

# ❌ BAD: String interpolation
Repo.query("SELECT * FROM users WHERE id = #{user_id}")
```

### Secret Management

- Use environment variables
- Never commit `.env` files
- Rotate secrets regularly
- Use different secrets per environment

## Documentation Standards

### Required Documentation

#### File Headers

```elixir
@moduledoc """
Service purpose and responsibilities.
Integration points and dependencies.
Configuration requirements.
"""
```

#### Complex Logic

```python
# Calculate exponential backoff with jitter
# to prevent thundering herd problem
delay = min(base * (2 ** attempt) + random.uniform(0, 1), max_delay)
```

#### Breaking Changes

Create ADR (Architecture Decision Record):

```markdown
# ADR-001: Refactor Twitch Service

## Status: Accepted

## Context: Service grew to 1691 lines

## Decision: Split into focused modules

## Consequences: Better maintainability
```

### Documentation Structure

```
/
├── README.md          # Project overview
├── STANDARDS.md       # This file
├── CLAUDE.md          # AI assistant rules
└── docs/
    ├── architecture/  # System design
    ├── adr/          # Decision records
    └── api/          # API documentation
```

## Pre-commit Hooks (Automated Enforcement)

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check for hardcoded secrets
grep -r "password\|secret\|token\|key" --include="*.ex" --include="*.py" --include="*.ts" | \
  grep -v "get_env\|System.fetch_env" && \
  echo "ERROR: Hardcoded secrets detected" && exit 1

# Check for wildcard CORS
grep -r "origins:.*\*" --include="*.ex" && \
  echo "ERROR: Wildcard CORS detected" && exit 1

# Check for shell=True
grep -r "shell=True" --include="*.py" && \
  echo "ERROR: Unsafe shell execution detected" && exit 1

# Run formatters and tests
bun run precommit
```

## Performance Standards

### Database

- Connection pool: 10-20 connections
- Query timeout: 15 seconds
- Batch inserts when possible
- Index foreign keys

### WebSocket

- Reconnect with exponential backoff
- Maximum 200 queued messages
- Batch events with 50ms window
- Circuit breaker for failures

### Frontend

- Lazy load components
- Virtualize long lists
- Cleanup animation contexts
- Debounce user input

## Enforcement

### Automated Tools

#### Setup

```bash
# Install pre-commit hooks
bun run setup:hooks

# Run all checks
bun run validate
```

#### Configuration Files

- `.formatter.exs` - Elixir formatting
- `pyproject.toml` - Python tools
- `.eslintrc.json` - TypeScript linting
- `.prettierrc` - Code formatting

### Review Checklist

Before merging any PR:

- [ ] Security: No :public ETS tables
- [ ] Security: Authentication verified
- [ ] Code: Follows language standards
- [ ] Tests: Coverage requirements met
- [ ] Docs: Updated if needed
- [ ] Performance: No obvious bottlenecks

## Implementation Timeline

### Week 1: Security Hardening (CRITICAL)

**Day 1 - MANDATORY**

1. Implement API authentication
2. Fix CORS configuration (no wildcards)
3. Add rate limiting
4. Enable security headers

**Days 2-7**

1. Encrypt stored tokens
2. Fix command injection vulnerabilities
3. Add input validation
4. Set up TypeScript test infrastructure

### Week 2: Quality Improvements

1. Begin Twitch service decomposition (<500 lines)
2. Write WebSocket manager tests
3. Write layer orchestrator tests
4. Fix memory leaks in GSAP animations

### Week 3-4: Polish

1. Add Python test infrastructure
2. Implement error boundaries
3. Generate API documentation
4. Set up monitoring dashboard

## Exceptions

Exceptions to these standards require:

1. Documented reason in code
2. ADR for architectural changes
3. Security review for any auth changes
4. Performance testing for bottlenecks

## Success Metrics

### 30-Day Targets

- ✅ Zero critical security vulnerabilities
- ✅ API authentication on all endpoints
- ✅ TypeScript test infrastructure operational
- ✅ Twitch.ex reduced to < 500 lines
- ✅ 60% overall test coverage

### 60-Day Targets

- ✅ All services < 500 lines per file
- ✅ Complete API documentation
- ✅ Monitoring dashboard functional
- ✅ Zero memory leaks
- ✅ Automated security scanning

## Decision Framework

For every technical decision, ask:

1. **Is this secure?** → If no, stop
2. **Is this personal scale?** → If enterprise, simplify
3. **Does this provide user value?** → If no, skip
4. **Is there a simpler option?** → Start there
5. **Will this scale if needed?** → Basic extensibility

## Version History

- **v2.0.0** (2025-08-07): Complete rewrite based on multi-model consensus
  - Security-first approach after critical vulnerability findings
  - Personal scale filter to avoid over-engineering
  - Metrics as signals, not gates
  - Pragmatic test coverage targets (60% vs 80%)
- **v1.0.0** (2025-07-17): Initial standards

---

_These standards are enforced through automated tooling and peer review. When in doubt, prioritize security and maintainability over performance._

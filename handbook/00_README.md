# Landale Developer Handbook

> Personal knowledge base for future you - not tutorials, just memory augmentation
>
> **⚠️ DEPRECATION NOTICE**: This handbook is from July 2025 and contains outdated information.
> For current patterns and accurate project state, refer to:
>
> - **CLAUDE.md** - Current development patterns and instructions
> - **PROJECT-CONTEXT.md** - Accurate project status and test coverage
> - **STANDARDS.md** - Current coding standards
>
> This handbook remains for historical reference only.

## What This Is

This handbook contains the patterns, decisions, and context I need to remember when working on the Landale streaming overlay system. It's organized around "things I figured out" and "choices I made" rather than formal documentation.

## Quick Navigation

### 🎯 Vision & Goals

- **[AI Companion Vision](01_vision_and_goals/ai_companion.md)** - Why this project exists and how I think about my stream

### 🏗️ Architecture

- **[System Overviews](02_architecture/system_overviews/)** - How complex parts work
  - [Stream Correlation System](02_architecture/system_overviews/stream_correlation_system.md)
  - [Event to Layer Mapping](02_architecture/system_overviews/event_to_layer_mapping.md)
  - [IronMON Integration](02_architecture/system_overviews/ironmon_integration.md)
- **[Architecture Decisions](02_architecture/decisions/)** - Why I chose specific technologies

### 🧠 Patterns & Practices

- **[Phoenix Channel Resilience](03_patterns_and_practices/phoenix_channel_resilience.md)** - WebSocket patterns that work
- **[GSAP Memory Management](03_patterns_and_practices/gsap_memory_management.md)** - Animation cleanup patterns
- **[Async Operation Lifecycle](03_patterns_and_practices/async_operation_lifecycle.md)** - Timer and cleanup patterns
- **[Correlation ID Tracing](03_patterns_and_practices/correlation_id_tracing.md)** - Request tracing across services

### 🔧 Operations

- **[macOS Setup](04_operations/macos_setup.md)** - Getting Nurvus running on macOS

### 🚀 Future Work

- **[Refactor Candidates](05_future_work/refactor_candidates.md)** - Things that need attention
- **[Wishlist](05_future_work/wishlist.md)** - Ideas worth pursuing

## Project Context

- **Personal-scale architecture**: Single user, Tailscale networking, no enterprise complexity
- **Event-driven core**: Phoenix WebSocket hub with correlation IDs everywhere
- **Resilient by design**: Fail fast, restart clean, circuit breakers on external calls
- **Stack**: Bun (not Node), SolidJS, Elixir Phoenix, PostgreSQL + TimescaleDB

---

_This handbook replaces scattered documentation with consolidated knowledge for efficient context switching._

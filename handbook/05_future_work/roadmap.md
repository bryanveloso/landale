# Future Work and Ideas

> Feature wishlist and improvement opportunities

**Last Updated**: 2025-08-05

## Recently Completed (July-August 2025)

### WebSocket Standardization

- ✅ Standardized heartbeat interval to 15s across all services (6x safety factor)
- ✅ Created centralized WebSocket configuration in shared package
- ✅ Refactored all components to use resilient Socket wrapper
- ✅ Fixed "hundreds of heartbeat failures" issue
- ✅ Added comprehensive WebSocket telemetry tracking

### Lessons Learned

- **Standardization matters**: takeover.tsx was initially missed, showing need for systematic checking
- **Heartbeat timing crucial**: 30s interval with 90s timeout (3x factor) was insufficient
- **Centralized config prevents drift**: Single source of truth for all WebSocket settings
- **Debug tools essential**: Can't fix what we can't see or reproduce

## Immediate Priorities (Next 2 Weeks)

### 1. Debug Interface Enhancement

**Goal**: Debug any overlay issue in <30 seconds

- Enhance `window.landale_debug` with comprehensive event triggers
- Add query param debug modes (?debug=true, ?debug=events, ?debug=perf)
- Create comprehensive debug documentation
- **Why now**: Recent heartbeat issues showed critical need for debugging tools

### 2. Alert Queue System

**Goal**: Prevent notification overlap for professional viewer experience

- Implement FIFO queue with configurable durations (follow=5s, sub=8s, raid=10s)
- Add audio feedback per event type
- Port proven patterns from overlay-main reference
- **Why now**: User experience requires smooth notification flow

### 3. Telemetry Dashboard

**Goal**: Visualize the telemetry we're already collecting

- Display real-time WebSocket stats (heartbeat success rate, reconnections)
- Add memory usage monitoring and alerts
- Export functionality for debugging sessions
- **Why now**: We collect data but can't see it - "can't fix what we can't see"

### 4. Protocol Documentation

**Goal**: Prevent regressions like the OBS v5 auth issue

- Document OBS WebSocket v5 auth flow
- Document Phoenix channel protocols
- Add "Protocol Preservation" to refactor checklist
- **Why now**: Critical knowledge shouldn't live only in code

## High Priority Features

### Integrated Chat

- Reference: https://github.com/honeykingdom/honey-chat
- Integration with existing overlay system
- Channel point rewards integration
- This lives in the dashboard, but needs to be verified that it works

### Omnibar Reimplementation

Original implementations for reference:

- https://github.com/bryanveloso/synthform-2017/tree/master/app/channels/avalonstar
- https://github.com/avalonstar/synthform/tree/master/src/clients/avalonstar/components
- This already exists in the current overlay system, but needs to be reassessed and styled (Bryan to take lead on styling)

### Text-to-Speech for Messages

- Platform: https://elevenlabs.io/
- Channel point or tipped message triggers
- Voice customization options

## Medium Priority Features

### External Integrations

- **LiveSplit integration**: Run timing and splits display
- **VTubeStudio integration**: Avatar interaction with stream events

## Low Priority Features

### Development Infrastructure

- **Test coverage setup**: Comprehensive testing strategy
- **Monitoring/metrics dashboard**: Performance and health monitoring
  - This lives in the dashboard, but needs to be verified that it works
- **Historical display state tracking**: Analytics for stream optimization

## Recent Accomplishments

### August 2025

- **WebSocket Standardization**: Complete overhaul of WebSocket configuration
  - Reduced heartbeat interval from 30s to 15s (6x safety factor)
  - Centralized configuration in shared package constants
  - Eliminated all direct Phoenix Socket usage
  - Fixed persistent heartbeat timeout failures
- **Telemetry Infrastructure**: WebSocketStatsTracker implementation
  - Real-time connection health monitoring
  - Reconnection event tracking
  - Foundation for telemetry dashboard

### July 2025

- **Debug Interface**: Partial implementation of window.debug
  - Basic event triggering capabilities
  - Foundation for comprehensive debugging
- **Circuit Breaker**: Refactored to CircuitBreakerServer pattern
  - Proper GenServer implementation
  - Prevents cascade failures from external services

### June 2025

- **Architecture & Performance**
  - Display manager architecture refactor
  - Type safety improvements (removed all `any` types)
  - Performance optimizations for 60fps streaming
  - WebSocket reliability improvements (initial work)
- **Security & Operations**
  - Security hardening (API keys, credentials)
  - Docker optimization (multi-stage builds, layer caching)
  - Error boundaries for all overlay routes

## Legacy Features (Completed)

### Interactive Elements

- After Dark Flying Toasters screensaver
- Customizable emote rain settings via dashboard
- Status bar toggles and customizable text

### External Integrations

- Dashboard controls for OBS
- Rainwave.cc integration (currently playing)
- Apple Music integration (currently playing via host monitor)

## Refactor Candidates

See also:

- [Event to Layer Mapping](../02_architecture/system_overviews/event_to_layer_mapping.md) - High priority refactor

## Architectural Improvements (Month 2)

### Broadcast-Only Channel

- Add `overlay:broadcast` Phoenix topic for simple fire-and-forget events
- Keep complex channels only for stateful features
- Enable rapid creative development without enterprise patterns
- **Lesson**: Not everything needs full Phoenix channel complexity

### Simplicity Layer

- Implement dual-pattern architecture (enterprise + simplicity)
- Create templates for common overlay patterns
- Document when to use each approach
- **Goal**: Make the right thing easy

## Ideas from Other Overlay Systems (January 2025)

Based on analysis of two popular overlay systems, these features could enhance Landale:

### From overlay-main (DoceAzedo's System)

- **Alert Queue System**: Prevents notification overlap by processing alerts sequentially with configurable durations. Uses simple array with sleep-based timing. Critical for professional viewer experience.

  ```typescript
  // Example: Each alert type has different duration
  const ALERT_DURATION_MAP = {
    follow: 5000,
    sub: 8000,
    raid: 10000
  }
  ```

- **Debug Console Functions**: Expose `window.landale_debug` object for instant testing without backend events

  ```javascript
  window.debug = (username) => queueAlert({ type: 'follow', username })
  window.debug2() // Triggers multiple test events at once
  ```

- **Audio Feedback System**: Different preloaded sounds per event type (follow, sub, raid) creating information hierarchy through audio

- **Ultra-Simple WebSocket Broker**: 10-line broadcast-everything pattern for non-critical events

  ```typescript
  socket.onAny((event, ...args) => io.emit(event, ...args))
  ```

- **Shell Script Integration**: Bridge to OS-level automation (Spotify control, system notifications)

### From overlays-main (Next.js System)

- **Parametric Stinger Animations**: Community-contributable transition animations as pure functions

  ```typescript
  export const animation: StingerAnimation = {
    initFn: () => ({ duration: 2000 }),
    stateFn: ({ x, y, time }) => calculateDotState(x, y, time),
    fps: 10
  }
  ```

  - No pre-rendered assets needed
  - FPS control per animation
  - Debug mode with `?debug=true` query param

- **Audio Spectrum Visualizer**: Real-time frequency analysis using Canvas API
  - Targets specific audio device ("Stream Audio")
  - Creates ambient visuals synchronized to audio
  - Efficient canvas-based rendering

- **Creative Particle Systems**: Confetti and visual celebrations (though their 30+ element approach is performance-heavy)

### Architectural Patterns Worth Considering

- **Broadcast-Only Mode**: Add `overlay:broadcast` Phoenix topic for simple fire-and-forget events, keeping complex channels only for interactive features

- **Debug Query Parameters**: `?debug=true` enables visual debugging aids (borders, state info)

- **Simplicity Layer**: Maintain enterprise-grade core for critical features but add simple patterns for rapid creative development

### What NOT to Copy

- Face detection/NSFW filtering (overengineering for personal use)
- Custom HTTP proxy (Phoenix handles this already)
- Server-side controller pattern (unnecessary abstraction)
- 30+ particle animations (use GSAP instead)

## Implementation Notes

When implementing these features:

1. **Follow established patterns** from existing implementations
2. **Use layer orchestration** for visual elements
3. **Maintain personal-scale architecture** - avoid over-engineering
4. **Test with current WebSocket resilience patterns**
5. **Debug-first development** - Add debug capabilities before features
6. **Check protocol documentation** before any refactoring
7. **Standardize first** - Ensure consistency across all components

## Success Metrics

- **Reliability**: 99.9% heartbeat success rate
- **Debuggability**: Resolve any overlay issue in <30 seconds
- **Maintainability**: Zero protocol regression incidents
- **Developer Experience**: New developers productive in <1 hour

## Technical Debt Tracking

### Addressed

- ✅ WebSocket heartbeat timing issues
- ✅ Inconsistent Socket implementations
- ✅ Circuit breaker pattern (now CircuitBreakerServer)

### Outstanding

- ⚠️ Telemetry visualization gap
- ⚠️ Debug tooling incomplete
- ⚠️ Protocol documentation missing
- ⚠️ Alert queue for notifications

---

_This roadmap reflects the personal nature of the streaming setup - focused on useful features rather than enterprise complexity. Updated based on lessons from WebSocket standardization work._

# Future Work and Ideas

> Feature wishlist and improvement opportunities

**Last Updated**: 2025-08-06

## Major Architectural Wins (August 2025)

### Phoenix Direct Connection Architecture

- ✅ **Simplified WebSocket connections** - Direct Phoenix.js usage via phoenix-connection.ts (68 lines)
- ✅ **Reduced wrapper complexity** - Eliminated custom WebSocket abstractions in favor of Phoenix patterns
- ✅ **WebSocketTracker for connection lifecycle** - Uses Phoenix.Tracker for proper disconnection detection
- ✅ **Improved reliability and maintainability** - Direct connections more stable than custom wrappers

### Production Service Management

- ✅ **Real-time service control through dashboard** - Start/stop/restart services via UI
- ✅ **Cross-environment deployment support** - macOS LaunchAgent + Linux systemd with template system
- ✅ **Environment-aware logging and telemetry** - Prevents development noise in production monitoring
- ✅ **Service health monitoring with cascade detection** - Real-time status updates and health checks

### Development Experience Revolution

- ✅ **Systematic pre-commit validation** - Catches critical portability issues before commit
- ✅ **Template-based deployment configurations** - Portable across users and environments
- ✅ **Environment detection system** - Automatic OBS/Tauri/development/production context awareness
- ✅ **Fixed critical service crashes** - SEED service reliability with proper WebSocket inheritance

### Implementation Lessons (August 2025)

- **Architecture simplification beats complex monitoring** - Removed need for telemetry dashboards by simplifying core architecture
- **Direct Phoenix connections more reliable than custom wrappers** - Eliminated entire class of connection issues
- **Template deployments prevent environment-specific failures** - Single configuration works across all users and machines
- **Systematic validation catches critical issues early** - Pre-commit validation prevented production failures

## Immediate Priorities (Next 2-4 Weeks)

### 1. Notification System Integration

**Goal**: Professional notification experience for stream viewers  
**Status**: Components exist (useNotificationQueue, overlay components) - needs orchestration

- Integrate existing notification components into cohesive system
- Implement FIFO queue with configurable durations (follow=5s, sub=8s, raid=10s)
- Add smooth animation sequences to prevent overlap
- **Why now**: Foundation exists, integration will deliver immediate user value

### 2. Debug Tools Completion

**Goal**: Debug any overlay issue in <30 seconds  
**Status**: window.debug exists, query params partially implemented

- Complete comprehensive event triggering capabilities
- Add query param debug modes (?debug=true, ?debug=events, ?debug=perf)
- Create debug documentation and help system
- **Why now**: Foundation established, completion unlocks rapid development

### 3. Service Health Cascade

**Goal**: Automatic service restart/management based on health status  
**Status**: Health monitoring exists, cascade logic needs implementation

- Implement automated service restart on health failure
- Add cascade detection (dependent service failures)
- Create configurable health check policies
- **Why now**: Monitoring infrastructure complete, automation is next logical step

### 4. User Experience Polish

**Goal**: Stream-ready professional appearance and behavior  
**Status**: Core functionality works, needs visual/UX refinement

- Professional styling for all overlay components
- Smooth transitions and animations
- Responsive design for different stream layouts
- **Why now**: Infrastructure is solid, time to focus on viewer experience

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

### August 2025 - Architecture Transformation

- **Phoenix Direct Connection Revolution**: Fundamental architecture simplification
  - Removed 3000+ lines of custom WebSocket wrapper code
  - Eliminated WebSocketStatsTracker complexity
  - Created single phoenix-connection.ts utility for all connections
  - Achieved greater reliability through architectural simplification

- **Production Service Management**: Complete operational control system
  - Real-time service start/stop/restart through dashboard UI
  - Cross-platform deployment with macOS LaunchAgent + Linux systemd
  - Template-based configuration system for multi-user portability
  - Environment-aware logging prevents dev/prod confusion

- **Service Reliability & Health**: Production-grade monitoring and fixes
  - Fixed critical SEED service crashes with proper WebSocket inheritance
  - Implemented service health cascade detection
  - Environment detection system with automatic context awareness
  - Systematic pre-commit validation preventing deployment failures

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

When implementing new features (updated for Phoenix Direct architecture):

1. **Use Direct Phoenix Connections** - No custom WebSocket wrappers needed
2. **Follow phoenix-connection.ts patterns** - Centralized connection utility
3. **Leverage existing monitoring** - Service health and environment detection built-in
4. **Debug-first development** - Build on established window.debug foundation
5. **Template-based deployment** - Use established portable configuration patterns
6. **Maintain personal-scale simplicity** - Avoid enterprise over-engineering
7. **Pre-commit validation** - All changes go through systematic validation

## Success Metrics (Updated for Current Architecture)

- **Architectural Simplicity**: Maintain simplified Phoenix Direct architecture
- **Service Reliability**: Automated health cascade and self-healing services
- **Development Speed**: Debug any overlay issue in <30 seconds
- **Deployment Portability**: Single configuration works across all environments
- **User Experience**: Professional streaming presentation without technical complexity

## Technical Debt Status

### Major Debt Eliminated (August 2025)

- ✅ **Removed 3000+ lines of wrapper complexity** - Phoenix Direct architecture
- ✅ **Eliminated WebSocket monitoring overhead** - Architecture simplified to not need it
- ✅ **Fixed service reliability issues** - SEED crashes, orphaned processes resolved
- ✅ **Solved environment configuration problems** - Template-based deployment system
- ✅ **Established systematic validation** - Pre-commit hooks prevent regressions

### Remaining Technical Improvements

- **Notification System Integration** - Components exist, need orchestration
- **Debug Tools Completion** - Foundation exists, comprehensive features needed
- **Service Health Cascade** - Monitoring exists, automation needed
- **UX Polish** - Core functionality works, professional presentation needed

### No Longer Relevant

- ❌ **Telemetry visualization gap** - Architecture simplified to not need complex dashboards
- ❌ **Protocol documentation** - Phoenix Direct connections are self-documenting
- ❌ **WebSocket reliability concerns** - Solved through architectural simplification

---

_This roadmap reflects the completed architectural transformation of August 2025. Focus has shifted from infrastructure stability (complete) to user experience and feature development._

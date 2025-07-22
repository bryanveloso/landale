# Future Work and Ideas

> Feature wishlist and improvement opportunities

## High Priority Features

### Integrated Chat
- Reference: https://github.com/honeykingdom/honey-chat
- Integration with existing overlay system
- Channel point rewards integration

### Text-to-Speech for Messages
- Platform: https://elevenlabs.io/
- Channel point or tipped message triggers
- Voice customization options

### Omnibar Reimplementation
Original implementations for reference:
- https://github.com/bryanveloso/synthform-2017/tree/master/app/channels/avalonstar
- https://github.com/avalonstar/synthform/tree/master/src/clients/avalonstar/components

## Medium Priority Features

### External Integrations
- **LiveSplit integration**: Run timing and splits display
- **VTubeStudio integration**: Avatar interaction with stream events
- **Closed captioning**: Possibly via https://elevenlabs.io/

### Configuration System
- **Auto-generated dashboard controls** from display schemas
- **Display presets/templates** system for quick switching
- **Import/export** display configurations
- **A/B testing** for display variations

## Low Priority Features

### Development Infrastructure
- **Test coverage setup**: Comprehensive testing strategy
- **Monitoring/metrics dashboard**: Performance and health monitoring
- **Historical display state tracking**: Analytics for stream optimization

## Recent Accomplishments (June 2025)

### Architecture & Performance
- Display manager architecture refactor
- Type safety improvements (removed all `any` types)
- Performance optimizations for 60fps streaming
- WebSocket reliability improvements

### Security & Operations
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

## Implementation Notes

When implementing these features:
1. **Follow established patterns** from existing implementations
2. **Use layer orchestration** for visual elements
3. **Maintain personal-scale architecture** - avoid over-engineering
4. **Test with current WebSocket resilience patterns**

---

*This roadmap reflects the personal nature of the streaming setup - focused on useful features rather than enterprise complexity*
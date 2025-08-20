# Landale Development Roadmap

_Personal streaming overlay system - Updated 2025-08-18_

## Executive Summary

Landale has evolved significantly with the completion of core RAG (Retrieval Augmented Generation) integration and community vocabulary system. The primary focus now shifts to SEED service evolution and creative AI collaboration experiments.

**Current Status**: Core infrastructure complete, RAG system operational
**Next Phase**: AI exobrain research and experimentation
**Timeline**: Ongoing research-driven development

---

## Recent Completed Work ✅

### RAG System Integration (Complete)

- ✅ RAG query processing with LM Studio integration
- ✅ Community vocabulary system integration
- ✅ Stream terminology and context understanding
- ✅ Real-time data retrieval from Phoenix server
- ✅ Natural language queries about streaming data
- ✅ WebSocket resilience patterns
- ✅ Memory management and bounded queues

### Infrastructure Stability (Complete)

- ✅ Event-driven architecture with Phoenix PubSub
- ✅ Multi-service coordination (Phononmaser, SEED, Nurvus)
- ✅ Tailscale network security (no auth needed internally)
- ✅ Health monitoring across services
- ✅ Circuit breaker patterns for external APIs

## Current Development Focus

### SEED Evolution: Data Processor → Creative Exobrain

**Research Question**: Can SEED evolve from intelligent data analysis to genuine creative collaboration that understands stream personality and community dynamics?

**Challenge**: Moving beyond "fashion influencer looking at paleontology report" - making AI understand the _feel_ and _personality_ of streaming, not just the data.

---

## Active Research Areas

### Phase 1: SEED Exobrain Experiments (Current)

**Goal**: Transform SEED from data processor into creative collaborator

**Research Framework**:

```
Parameter Exploration          Model Comparison              Data Engineering
┌─────────────────┐           ┌─────────────────┐           ┌─────────────────┐
│ • Temperature   │           │ • Local vs API  │           │ • Raw vs        │
│ • Top-p         │──────────▶│ • Model sizes   │──────────▶│   Processed     │
│ • Rep penalty   │           │ • Specialization │           │ • Timeline vs   │
│ • Context len   │           │ • Fine-tuning    │           │   Emotional arc │
└─────────────────┘           └─────────────────┘           └─────────────────┘
```

#### Current Experiments

1. **Model Parameter Mapping** (Ongoing)
   - Testing temperature ranges for creativity vs accuracy
   - Finding optimal top-p settings for stream context
   - Documenting which parameters affect personality understanding

2. **Prompt Architecture Research**
   - System vs user prompts for personality establishment
   - Few-shot examples with successful "exobrain" responses
   - Role-playing prompts that establish creative collaboration context

3. **Data Structure Experiments**
   - Narrative presentation vs structured data
   - Including emotional context and streamer reactions
   - Timeline-based vs topic-based data organization

4. **Community Feature Integration** (Ready for Implementation)
   - **Username Dictionary**: ✅ COMPLETED via PromptManager in Phononmaser
   - **Vocabulary/Inside Joke Tracking**: Pattern detection and storage for recurring phrases, memes, catchphrases
   - **Long-term Community Memory**: Aggregation layer for "who said what when" queries
   - **Enhanced Context Building**: Rich community data already captured (chat, emotes, interactions)

#### Success Criteria

- Can SEED suggest genuinely creative "you know what would be funny if..." ideas?
- Does it understand callback humor and community inside jokes?
- Can it handle "hey remember that time when..." queries with personality?

### Phase 2: Infrastructure Optimization (As Needed)

**Pragmatic Approach**: Address issues only when they impact development or streaming

#### Potential Areas (Not Prioritized)

- Frontend test coverage (currently minimal)
- Python service test expansion
- Memory optimization if GSAP issues emerge
- Database indexing for query performance

**Note**: Given Tailscale network security, authentication work is deprioritized unless specific need emerges.

### Phase 3: Creative Feature Development (Future)

Based on SEED research outcomes:

1. **If Exobrain Succeeds**:
   - Stream preparation assistant ("Today you should try...")
   - Real-time creative suggestions during stream
   - Community mood and energy analysis
   - Callback and running gag tracking

2. **If Exobrain Limited**:
   - Focus on data analysis and insights
   - Enhanced activity reporting
   - Pattern recognition and trends
   - Historical stream analysis

### Phase 4: User Interface Enhancements

#### RAG Query Dashboard Interface

**Current Status**: RAG system operational via HTTP API and WebSocket, but requires terminal/curl for queries

**Goal**: Create intuitive dashboard UI for RAG queries to eliminate terminal dependency

**Components Needed**:

- Dashboard RAG query panel with natural language input
- Query history and favorites
- Real-time response display with confidence indicators
- Example query suggestions organized by category
- Export functionality for insights and reports

**Integration Points**:

- Leverage existing `/api/activity/` endpoints for data context
- Use established Phoenix WebSocket channels for real-time queries
- Follow component factory pattern from activity log for response rendering
- Maintain JSON data structure for rich formatting and emote support

**User Experience**:

- Quick query bar: "Ask about your stream..."
- Category shortcuts: Subs, Follows, Chat, Stream Stats, Mood Analysis
- Response formatting with confidence levels and data sources
- Shareable query results for stream preparation notes

**Technical Approach**:

- SolidJS component following established dashboard patterns
- HTTP API integration with `POST http://localhost:8891/query`
- Real-time WebSocket updates via `rag_query`/`rag_response` events
- JSON response rendering with emote support and user badge display

#### User Management Dashboard Interface

**Current Status**: Activity log infrastructure complete, user metadata schema exists
**Goal**: Create comprehensive user management for moderation and personalization

**Core Features**:

- User search/lookup by Twitch login with autocomplete
- Edit user nicknames (display name override)
- Set user pronouns (they/them, she/her, he/him, custom)
- Add moderation notes for user context
- View user-specific activity history timeline

**UI Components**:

- `UserManagementPanel` component with search input
- User profile card with editable fields
- Pronouns dropdown with common options + custom input
- Notes textarea for moderator context
- Activity timeline for selected user

**Technical Implementation**:

- Create `useUserManagement` hook for API integration
- Add user CRUD API endpoints to existing activity log controller
- Extend user search and activity filtering capabilities
- Integration with existing Activity Log infrastructure and EventHandler user resolution

**Integration Points**:

- Leverage existing `activity_log_users` table schema
- Use established Phoenix API patterns for CRUD operations
- Follow component factory pattern from activity log for timeline rendering
- Maintain JSON data structure for rich user activity display

#### Notification System Implementation

**Status**: Not implemented - design documentation was removed 2025-08-20
**Priority**: Medium - would enhance streaming overlays with real-time viewer engagement

**Overview**: A comprehensive notification system for handling Twitch events (follows, subscriptions, cheers, raids) with priority-based queuing, audio playback, and visual animations integrated with the existing layer orchestrator.

**System Architecture Design**:

```
Phoenix Channel → NotificationManager → Overlay Display
(twitch_event)   (Queue & Priority)    (SolidJS Components)
       ↓               ↓                      ↓
ConfigLoader     AudioManager        GSAP Layer Orchestrator
(JSON + Zod)     (Web Audio API)     (Existing Animation System)
```

**Core Components to Build**:

1. **NotificationManager** (`apps/overlays/src/services/notification-manager.ts`)
   - Priority queue (1-10 scale, higher priority interrupts lower)
   - Memory protection with MAX_QUEUE_SIZE = 50
   - Atomic processing with locks to prevent race conditions
   - SolidJS reactive signals for UI integration
   - Lifecycle management (subscribe/unsubscribe callbacks)
   - Queue control (pause/resume/clear functionality)

2. **AudioManager** (`apps/overlays/src/services/audio-manager.ts`)
   - Web Audio API or Howler.js for sound playback
   - Audio normalization to -16 LUFS standard (ffmpeg preprocessing)
   - Preload pools: 3 instances per sound file for overlap handling
   - Volume control with localStorage persistence
   - Mute toggle functionality
   - User interaction requirement for browser audio policy compliance

3. **ConfigLoader** (`apps/overlays/src/services/config-loader.ts`)
   - Zod schemas for type-safe configuration validation
   - JSON configuration files (`/public/config/notifications.json`)
   - Discriminated unions for event-specific fields
   - Specificity-based matching algorithm (exact > range conditions)
   - Hot reload capability without service restart
   - Fallback to defaults on configuration errors

**Event Type Support**:

- `channel.follow` - New followers
- `channel.subscribe` - Subscriptions with tier support (1000/2000/3000)
- `channel.subscription.gift` - Gift subscriptions with anonymous flag
- `channel.cheer` - Bit cheers with amount ranges and exact matching
- `channel.raid` - Incoming raids with viewer count thresholds
- `channel.channel_points_custom_reward_redemption` - Channel point rewards

**Configuration Schema Example**:

```json
{
  "version": "1.0",
  "configs": [
    {
      "id": "follow-default",
      "condition": { "type": "channel.follow" },
      "audio": "/audio/notifications/follow.ogg",
      "priority": 3,
      "duration": 5000
    },
    {
      "id": "cheer-meme",
      "condition": {
        "type": "channel.cheer",
        "bits": { "exact": 420 }
      },
      "audio": "/audio/notifications/meme-sound.ogg",
      "priority": 10,
      "duration": 10000
    },
    {
      "id": "raid-large",
      "condition": {
        "type": "channel.raid",
        "viewers": { "min": 100 }
      },
      "audio": "/audio/notifications/raid-epic.ogg",
      "priority": 9,
      "duration": 15000
    }
  ]
}
```

**Debug Interface** (`window.debug.notifications`):

- Test individual event types with realistic data
- Burst testing for queue overflow scenarios
- Queue status monitoring (length, processing state, current notification)
- Audio testing with volume controls
- Configuration reload without restart
- Memory usage monitoring

**Integration Points**:

- Phoenix WebSocket channels for real-time Twitch events
- Existing GSAP layer orchestrator for notification animations
- SolidJS reactive patterns matching dashboard components
- Component factory pattern from activity log implementation
- Audio file storage in `/public/audio/notifications/` directory

**Implementation Considerations**:

- Follow established bounded queue patterns (see SEED/Phononmaser services)
- Use singleton pattern for manager instances
- Implement proper cleanup in SolidJS onCleanup hooks
- Browser audio policy requires user interaction before playback
- Queue processing should be sequential but non-blocking
- Memory protection crucial for long streaming sessions

**Testing Requirements**:

- Unit tests for priority queue logic and configuration matching
- Integration tests with mock Phoenix channels
- Load testing with burst event scenarios (200+ events/second)
- Audio playback testing across browsers
- Configuration validation with invalid schemas
- Memory leak detection for extended operation

**Performance Targets**:

- Sub-1ms configuration lookup
- <50ms queue processing latency
- Memory usage <100MB for 8-hour streaming session
- Audio preloading <5 seconds on page load
- Configuration hot reload <200ms

**Future Enhancements**:

- Visual animation presets per notification type
- Custom CSS classes per configuration
- A/B testing different notification styles
- Analytics tracking for engagement metrics
- WebSocket reconnection with queue persistence

### Phase 5: Advanced Community Features (Future Phases)

#### Vocabulary & Inside Joke Tracking

**Current Capability**: Rich community data already captured in `_build_rich_context_data()`
**Ready to Implement**: Pattern detection and storage system

**Architecture Approach**:

```sql
CREATE TABLE community_vocabulary (
  phrase TEXT PRIMARY KEY,
  phrase_type TEXT CHECK (phrase_type IN ('joke', 'meme', 'catchphrase', 'term')),
  first_occurrence TIMESTAMPTZ,
  usage_count INTEGER DEFAULT 1,
  context_examples JSONB DEFAULT '[]',
  related_emotes TEXT[],
  confidence_score FLOAT DEFAULT 0.5
);
```

**Detection Algorithm**:

```python
class VocabularyTracker:
    def __init__(self, threshold: int = 5):
        self.phrase_candidates: Counter = Counter()
        self.threshold = threshold

    async def analyze_message(self, message: ChatMessage):
        phrases = self._extract_phrases(message.message)
        for phrase in phrases:
            self.phrase_candidates[phrase] += 1
            if self.phrase_candidates[phrase] == self.threshold:
                await self._promote_to_vocabulary(phrase, message)
```

#### Enhanced Vector Search (Lessons Learned Applied)

**Previous Implementation**: Rolled back due to architectural issues
**Critical Requirements for Future Implementation**:

1. **Design Phoenix API endpoints FIRST** - Don't build clients for non-existent endpoints
2. **Use dependency injection** - Avoid direct imports between services
3. **Single-purpose classes** - No god objects over 200 lines
4. **Test-driven architecture** - Ensure all components are unit testable

**Recommended Architecture**:

```python
@runtime_checkable
class ContextRepository(Protocol):
    async def vector_search(self, embedding: list[float], limit: int) -> list[dict]: ...

class RAGQueryEngine:
    def __init__(self, context_repo: ContextRepository):
        self.context_repo = context_repo  # Dependency injection
```

#### Community Insights & Analytics

**Real-time Community Events**:

```python
async def _detect_community_moments(self):
    if self._is_vocabulary_milestone():
        await self._emit_event("vocabulary_milestone", {...})
    if self._is_engagement_spike():
        await self._emit_event("community_energy_spike", {...})
```

**Analytics Endpoints** (Server enhancement):

```elixir
def community_stats(conn, %{"hours" => hours}) do
  stats = %{
    active_members: Context.count_active_members(hours),
    vocabulary_trends: Context.get_vocabulary_trends(hours),
    engagement_patterns: Context.get_engagement_patterns(hours),
    top_moments: Context.get_top_moments(hours)
  }
  json(conn, %{data: stats})
end
```

#### Success Metrics

- **Transcription Accuracy**: 20% improvement for community member names (achieved via PromptManager)
- **Vocabulary Detection**: 90% precision for repeated phrases
- **Query Response Time**: <2 seconds for historical queries
- **Memory Efficiency**: <500MB RAM with 1000 active members

---

## Testing & Quality Assurance Strategy

### Current Testing Status

- **Elixir (Server)**: 92 test files - comprehensive coverage
- **TypeScript (Frontend)**: 2 test files - critical gap requiring attention
- **Python Services**: 10 test files (~15% coverage, target 50-65%)

### High-Priority Testing Tasks

#### 1. Multi-Service Failure Handling Tests

**Priority: Critical** | **Value: Live streaming confidence**

Test system resilience during service failures:

- Phononmaser service restart during streaming
- Database unavailability during event logging
- OBS WebSocket disconnect during scene switching
- Network partitions via Tailscale connectivity issues
- Multi-service cascade failure prevention

**Implementation**: Create `Server.Testing.FailureOrchestrator` module building on existing `OBSTestHelpers` patterns

#### 2. RAG System Testing

**Priority: High** | **Value: Query accuracy validation**

Test the new RAG query interface:

- Session boundary detection accuracy
- Game context integration correctness
- Query response time under load
- Community data correlation precision
- Natural language understanding validation

#### 3. Dashboard Component Testing

**Priority: Medium** | **Value: Frontend stability**

Test rich activity log implementation:

- Component factory pattern for event types
- Emote rendering with fragments array
- JSON event data handling
- WebSocket resilience in overlay components
- GSAP animation lifecycle management

**User Management Testing**:

- User search autocomplete functionality
- CRUD operations for user profiles (nicknames, pronouns, notes)
- User activity timeline filtering and display
- Integration with existing activity log infrastructure
- Pronouns dropdown and custom input validation

**Notification System Testing**:

- Priority queue processing with concurrent events
- Audio playback and normalization validation
- Configuration hot reloading and Zod schema validation
- Debug interface functionality and burst testing
- Memory protection under sustained load (MAX_QUEUE_SIZE limits)
- Phoenix WebSocket integration with Twitch events

#### 4. Burst Event Processing Tests

**Priority: Medium** | **Value: Performance validation**

Validate performance under high-frequency loads:

- 200+ events per second sustained load
- Memory usage during burst processing
- Event ordering preservation
- Circuit breaker activation thresholds
- Queue overflow handling

### Database & Performance Optimization

#### TimescaleDB Enhancements

- **Continuous Aggregates**: Hourly/daily metrics for frequent queries
- **Compression Policies**: Transcription data older than 7 days
- **Retention Policies**: Auto-drop data older than 90 days
- **Text Search Optimization**: pg_trgm configuration and GIN indexes

#### Performance Targets

- Query response time: <2 seconds for historical data
- Memory efficiency: <500MB with 1000 active members
- Test execution: <5 minutes for CI compatibility
- Zero test flakiness with actionable failure information

### Implementation Guidelines

**When to Tackle Testing Tasks:**

- **High Energy Days**: Multi-service failure testing (immediate operational value)
- **Learning Days**: TypeScript test patterns (skill building opportunities)
- **Maintenance Days**: Database optimizations (systematic, low-risk improvements)

**Success Criteria:**

- Maintain existing functionality during improvements
- No performance regressions introduced
- Clear documentation of all changes
- CI integration where applicable
- Measurable improvements with before/after benchmarks

---

## Development Commands

### Current Development Workflow

```bash
# SEED Development
cd apps/seed
uv run python -m src.main  # Start SEED with RAG

# Test RAG queries
curl -X POST http://localhost:8891/query \
  -H "Content-Type: application/json" \
  -d '{"question": "What made chat excited during my last stream?"}'

# LM Studio for local model testing
# Access at: http://localhost:1234

# Monitor all services
bun dev  # Starts all workspaces
```

### Model Experimentation

```bash
# Test different temperature settings in LM Studio
# Temperature 0.1: Very focused, analytical
# Temperature 0.8: Creative, personality-aware
# Temperature 1.2: Very creative, potentially chaotic

# Document findings in issue #42:
# https://github.com/bryanveloso/landale/issues/42
```

---

## Architecture Status

### What's Working ✅

- **Event-driven architecture**: Solid foundation for real-time data
- **WebSocket resilience**: Services reconnect automatically
- **Memory management**: Bounded queues prevent exhaustion
- **Health monitoring**: All services report status
- **RAG integration**: Query streaming data with natural language
- **Vocabulary system**: Understands stream terminology

### What's Experimental 🔬

- **SEED exobrain capabilities**: Core research question
- **Creative AI collaboration**: Unknown feasibility
- **Personality modeling**: Requires systematic testing
- **Context understanding**: Beyond data analysis

### What's Deferred ⏸️

- **Authentication systems**: Not needed on Tailscale
- **Frontend testing**: Not blocking current development
- **Performance optimization**: Current performance acceptable
- **CI/CD complexity**: Simple workflows sufficient

---

## Decision Framework

### When to Address Technical Debt

1. **Blocks streaming**: Fix immediately
2. **Blocks SEED research**: Fix as needed
3. **Code quality concerns**: Address during natural refactoring
4. **Security on public internet**: Not applicable (Tailscale)

### When to Add New Features

1. **Supports SEED research**: High priority
2. **Enhances streaming experience**: Medium priority
3. **Improves development workflow**: Low priority
4. **"Nice to have"**: Document but don't build

---

## Resources and Links

- **Issue #42**: SEED Evolution Strategy
- **LM Studio**: Local model hosting and testing
- **Current Todo**: Focus on exobrain feasibility research
- **Architecture docs**: `handbook/` directory

---

## Next Immediate Steps

1. **Continue SEED experiments**: Test different prompt structures and model parameters
2. **Document findings**: Update issue #42 with experimental results
3. **Iterate on personality**: Test whether AI can develop stream-specific understanding
4. **Evaluate feasibility**: Determine if exobrain vision is achievable or if pivot needed

---

_Updated roadmap reflects current development reality: core infrastructure complete, focus shifted to AI research and creative collaboration experiments. Priorities align with personal project scale and Tailscale security model._

# Event to Layer Mapping Architecture

> How external events become overlay alerts - currently convoluted, refactor candidate

## Current Problem

The process of transforming external events into overlay alerts involves too many transformation steps and is difficult to follow. This document captures the current implementation for future refactoring.

## Current Flow (Convoluted)

```
External System → Event Publisher → PubSub → Event Handler → StreamProducer.add_interrupt → Layer Assignment → Overlay Display
```

**Too many transformation steps**:

1. External event → Generic PubSub event
2. Generic event → Specific alert type
3. Alert type → Layer priority assignment
4. Layer assignment → Overlay rendering

## Current Implementation

### Step 1: External Systems Publish Events

```elixir
# IronMON TCP message
Server.Events.publish_ironmon_event("pokemon_death", %{
  pokemon: "Charizard",
  level: 45,
  cause: "critical_hit"
}, batch: false)

# Twitch EventSub
Server.Events.publish_twitch_event("channel.subscribe", %{
  user_name: "viewer123",
  tier: "1000"
})

# System events
Server.Events.publish_system_event("build_failure", %{
  project: "landale",
  error: "TypeScript compilation failed"
})
```

### Step 2: StreamProducer Subscriptions

**Missing subscriptions** (shows the incomplete nature):

```elixir
# In StreamProducer.init/1
Phoenix.PubSub.subscribe(Server.PubSub, "chat")
Phoenix.PubSub.subscribe(Server.PubSub, "followers")
Phoenix.PubSub.subscribe(Server.PubSub, "subscriptions")
Phoenix.PubSub.subscribe(Server.PubSub, "cheers")
Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")    # ← Missing
Phoenix.PubSub.subscribe(Server.PubSub, "system:events")     # ← Missing
```

### Step 3: Event Handler Conversion

**The missing piece** - manual event conversion:

```elixir
# Each event type needs a specific handler
def handle_info({:ironmon_event, %{type: "pokemon_death", data: data}}, state) do
  StreamProducer.add_interrupt(:death_alert, %{
    pokemon: data.pokemon,
    level: data.level,
    cause: data.cause,
    message: "#{data.pokemon} fainted at level #{data.level}!"
  })
  {:noreply, state}
end

def handle_info({:ironmon_event, %{type: "shiny_encounter", data: data}}, state) do
  StreamProducer.add_interrupt(:shiny_encounter, %{
    pokemon: data.pokemon,
    location: data.location,
    message: "✨ Shiny #{data.pokemon} encountered!"
  })
  {:noreply, state}
end
```

### Step 4: Layer Priority Assignment

**Hidden in layer coordination logic:**

- `:death_alert` → foreground layer (high priority)
- `:shiny_encounter` → foreground layer (rare event)
- `:build_failure` → midground layer (dev context)
- `:sub_train` → background layer (community context)

## Why This Is Problematic

**Too Many Manual Mappings**:

- Every external event needs a specific `handle_info` function
- Event type strings → Content type atoms conversion is manual
- Layer assignment logic is scattered across multiple modules

**Difficult to Extend**:

- Adding new event types requires code changes in multiple places
- No clear pattern for event → layer priority mapping
- Debugging event flow requires tracing through multiple modules

**Inconsistent Patterns**:

- Some events use generic types, others use specific atoms
- Priority assignment logic is not centralized
- Error handling varies by event type

## Refactor Opportunities

### Option 1: Event → Content Type Registry ✅ IMPLEMENTED

```elixir
# Centralized mapping configuration (NOW IN Server.LayerMapping)
@layer_mappings %{
  "ironmon" => %{
    "death_alert" => "foreground",
    "shiny_encounter" => "foreground",
    "checkpoint_cleared" => "background",
    # ... more mappings
  },
  "variety" => %{
    "raid_alert" => "foreground",
    "sub_train" => "midground",
    # ... more mappings
  }
}
```

> **Implemented**: Layer mappings are now centralized in `Server.LayerMapping` module. The StreamProducer enriches all events with a `layer` field before broadcasting.

### Option 2: Event Processing Pipeline

```elixir
# Single event processor with transformation pipeline
defmodule EventProcessor do
  def process_event(source, type, data) do
    source
    |> normalize_event(type, data)
    |> assign_content_type()
    |> assign_layer_priority()
    |> create_alert()
  end
end
```

### Option 3: Configuration-Driven Mapping

```elixir
# YAML/JSON configuration for event mappings
# events.yml
ironmon:
  pokemon_death:
    content_type: death_alert
    layer: foreground
    priority: 100
    message_template: "#{pokemon} fainted at level #{level}!"
```

## Current Integration Examples

### Pokemon Death Alert

```elixir
# Step 1: TCP receives "pokemon_death:charizard:45:critical_hit"
# Step 2: Publishes {:ironmon_event, %{type: "pokemon_death", data: %{...}}}
# Step 3: StreamProducer converts to :death_alert content type
# Step 4: Layer coordination assigns to foreground
# Step 5: Overlay displays with death alert styling
```

### Build Failure Alert

```elixir
# Step 1: CI webhook POST /api/webhooks/ci
# Step 2: Publishes {:system_event, %{type: "build_failure", data: %{...}}}
# Step 3: StreamProducer converts to :build_failure content type
# Step 4: Layer coordination assigns to midground (dev context)
# Step 5: Overlay displays with build failure styling
```

## Implementation Locations

**Event Publishers**: `apps/server/lib/server/events.ex`
**StreamProducer**: `apps/server/lib/server/stream_producer.ex`
**Layer Coordination**: `apps/server/lib/server/layer_mapping.ex`
**PubSub Topics**: Throughout various service modules

> **Update**: Layer mappings have been centralized to the server as of January 2025. Events now include a `layer` field enriched by the StreamProducer before broadcasting.

## Why This Needs Refactoring

1. **Too many transformation steps** slow down event processing
2. **Manual mapping** for every event type is error-prone
3. **Scattered logic** makes the system hard to debug and extend
4. **Inconsistent patterns** between different event sources
5. **No centralized configuration** for event → layer mappings

## Debugging Current System

**Event Flow Tracing**:

```elixir
# Add logging to StreamProducer
Logger.info("Converting event to alert",
  event_type: event_type,
  content_type: content_type,
  data: data
)
```

**PubSub Testing**:

```elixir
# Test events manually
Phoenix.PubSub.broadcast(Server.PubSub, "ironmon:events",
  {:ironmon_event, %{type: "pokemon_death", data: %{pokemon: "Pikachu"}}}
)
```

---

_This system works but is overly complex. The event → layer mapping should be simplified and centralized. Consider this a high-priority refactor candidate._

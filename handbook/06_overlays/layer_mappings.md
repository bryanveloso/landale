# Layer Mappings Guide

## Overview

Layer mappings define how different content types are assigned to visual layers in the streaming overlay system. The system uses a three-layer architecture (foreground, midground, background) to ensure proper visual hierarchy and prevent content conflicts.

> **Architecture Note**: As of January 2025, layer mappings are centralized on the Phoenix server in the `Server.LayerMapping` module. Frontend applications receive layer assignments via the `layer` field in events.

## Layer Architecture

### Visual Layer Hierarchy

```
┌─── Foreground ───┐  <- Highest priority, most visible
│                  │
│  ┌─ Midground ─┐ │  <- Medium priority, celebrations
│  │             │ │
│  │ Background  │ │  <- Lowest priority, ambient info
│  │             │ │
│  └─────────────┘ │
│                  │
└──────────────────┘
```

### Layer Purposes

- **Foreground**: Critical interrupts requiring immediate attention
- **Midground**: Celebrations and notifications that enhance the experience
- **Background**: Ambient information and ticker content

## Server-Side Layer Mapping

### Architecture

The `Server.LayerMapping` module serves as the single source of truth for all layer assignments. When events are broadcast through the system, the `StreamProducer` enriches them with layer information:

```elixir
# In Server.StreamProducer
defp enrich_state_with_layers(state) do
  enriched_active_content =
    if state.active_content do
      content_type = to_string(state.active_content.type)
      Map.put(state.active_content, :layer,
        Server.LayerMapping.get_layer(content_type, Atom.to_string(state.current_show)))
    else
      nil
    end
  # ... similar enrichment for interrupt_stack and ticker_rotation
end
```

### Show Context System

Layer mappings are context-aware and change based on the current show type:

- **Ironmon**: Pokémon challenge runs with game-specific alerts
- **Variety**: General streaming with community focus
- **Coding**: Development streams with build/deployment alerts

## Current Mappings

### Ironmon Show

```elixir
# Foreground - Critical interrupts
"death_alert" => "foreground"          # Pokémon death in challenge
"elite_four_alert" => "foreground"     # Elite Four encounter
"shiny_encounter" => "foreground"      # Shiny Pokémon found
"alert" => "foreground"                # Generic high-priority alert

# Midground - Celebrations and notifications
"level_up" => "midground"              # Pokémon level up
"gym_badge" => "midground"             # Gym badge earned
"sub_train" => "midground"             # Subscription train
"cheer_celebration" => "midground"     # Twitch cheer celebration

# Background - Stats and ambient info
"ironmon_run_stats" => "background"    # Current run statistics
"ironmon_deaths" => "background"       # Death counter
"recent_follows" => "background"       # Recent follower list
"emote_stats" => "background"          # Emote usage statistics
```

### Variety Show

```elixir
# Foreground - Breaking alerts
"raid_alert" => "foreground"           # Incoming raid notification
"host_alert" => "foreground"           # Being hosted by another streamer
"alert" => "foreground"                # Generic high-priority alert

# Midground - Community interactions
"sub_train" => "midground"             # Subscription train
"cheer_celebration" => "midground"     # Twitch cheer celebration
"follow_celebration" => "midground"    # New follower celebration

# Background - Community stats
"emote_stats" => "background"          # Emote usage statistics
"recent_follows" => "background"       # Recent follower list
"stream_goals" => "background"         # Stream goal progress
"daily_stats" => "background"          # Daily streaming statistics
```

### Coding Show

```elixir
# Foreground - Critical development alerts
"build_failure" => "foreground"        # Build failed
"deployment_alert" => "foreground"     # Deployment status
"alert" => "foreground"                # Generic high-priority alert

# Midground - Development celebrations
"commit_celebration" => "midground"    # Successful commit
"pr_merged" => "midground"             # Pull request merged
"sub_train" => "midground"             # Subscription train

# Background - Stream stats
"recent_follows" => "background"       # Recent follower list
"emote_stats" => "background"          # Emote usage statistics
```

## How Events Get Layer Assignments

### Event Flow

1. **Event Creation**: External system or manual trigger creates an event with a content type
2. **StreamProducer Processing**: Event is added to interrupt stack or set as active content
3. **Layer Enrichment**: Before broadcasting, `enrich_state_with_layers/1` adds layer field
4. **Frontend Receipt**: Overlay receives event with layer already assigned
5. **Layer Orchestration**: Frontend places content on appropriate visual layer

### Example Flow

```elixir
# 1. IronMON TCP service detects Pokemon death
StreamProducer.add_interrupt(:death_alert, %{
  pokemon: "Charizard",
  level: 45
})

# 2. StreamProducer enriches before broadcast
%{
  type: "death_alert",
  data: %{pokemon: "Charizard", level: 45},
  layer: "foreground",  # Added by Server.LayerMapping
  priority: 100
}

# 3. Frontend receives and renders on foreground layer
```

## API Functions

### Getting Layer for Content

```elixir
# Get layer for a specific content type and show
Server.LayerMapping.get_layer("death_alert", "ironmon")
# => "foreground"

# Supports both string and atom show names
Server.LayerMapping.get_layer("emote_stats", :variety)
# => "background"
```

### Getting All Mappings for a Show

```elixir
# Get all layer mappings for a show
Server.LayerMapping.get_mappings_for_show("ironmon")
# => %{
#   "death_alert" => "foreground",
#   "level_up" => "midground",
#   "ironmon_run_stats" => "background",
#   ...
# }
```

### Querying Layer Contents

```elixir
# Get all content types that map to a specific layer
Server.LayerMapping.get_content_types_for_layer("foreground", "ironmon")
# => ["death_alert", "elite_four_alert", "shiny_encounter", "alert"]

# Check if content should display on a layer
Server.LayerMapping.should_display_on_layer?("death_alert", "foreground", "ironmon")
# => true
```

## Adding New Layer Mappings

### Step 1: Update Server.LayerMapping

Add your new content type to the appropriate show mapping in `apps/server/lib/server/layer_mapping.ex`:

```elixir
@layer_mappings %{
  "ironmon" => %{
    # Existing mappings...
    "your_new_content_type" => "midground",  # Choose appropriate layer
  },
  # Add to other shows if needed
}
```

### Step 2: Create Event Trigger

Implement how your content type gets created:

```elixir
# External system integration
def handle_your_system_event(event_data) do
  StreamProducer.add_interrupt(:your_new_content_type, %{
    message: "Your event occurred!",
    specific_data: event_data.details
  })
end
```

### Step 3: Test Layer Assignment

```elixir
# Verify layer assignment
assert Server.LayerMapping.get_layer("your_new_content_type", "ironmon") == "midground"

# Test the enrichment
state = StreamProducer.get_current_state()
assert state.active_content.layer == "midground"
```

## Frontend Integration

### How Overlays Use Layer Information

The overlay components now use the server-provided layer field:

```typescript
// In omnibar.tsx
allContent.forEach((content) => {
  if (content && content.type && content.layer) {
    const targetLayer = content.layer as 'foreground' | 'midground' | 'background'

    // Assign to layer if higher priority than existing
    if (!layerContent[targetLayer] || content.priority > layerContent[targetLayer].priority) {
      layerContent[targetLayer] = content
    }
  }
})
```

### TypeScript Interface

```typescript
interface StreamContent {
  type: string
  data: unknown
  priority: number
  layer?: 'foreground' | 'midground' | 'background' // Server-provided
  // ... other fields
}
```

## Best Practices

### Layer Selection Guidelines

**Choose Foreground for:**

- Critical interrupts requiring immediate attention
- Time-sensitive alerts that cannot be missed
- Breaking news or emergency notifications
- Game-over scenarios or major failures

**Choose Midground for:**

- Celebrations and achievements
- Community interactions (subs, cheers, follows)
- Milestone notifications
- Non-critical but important updates

**Choose Background for:**

- Ambient information and statistics
- Ticker content that rotates
- Persistent data displays
- Low-priority informational content

### Consistency Principles

1. **Contextual Relevance**: Layer assignments should match the show's focus
2. **Visual Hierarchy**: Respect the three-layer system for proper UX
3. **Conflict Minimization**: Avoid putting too much content in foreground
4. **Cross-Show Consistency**: Similar content types should behave similarly across shows

## Troubleshooting

### Common Issues

**Content Not Appearing**:

- Check that the content type is mapped in `Server.LayerMapping`
- Verify the show context is correct
- Ensure event enrichment is happening in `StreamProducer`

**Wrong Layer Assignment**:

- Check the mapping in the server module
- Verify the content type string matches exactly

**Missing Layer Field**:

- Ensure you're using the enriched state from broadcasts
- Check that `enrich_state_with_layers/1` is being called

### Debugging

```elixir
# Server-side debugging
Server.LayerMapping.get_layer("content_type", "show")
Server.LayerMapping.get_mappings_for_show("ironmon")

# Check enriched state
state = Server.StreamProducer.get_current_state()
IO.inspect(state.active_content.layer)
```

```typescript
// Frontend debugging
console.log('Event received:', event)
console.log('Layer assignment:', event.layer)
```

## Migration Notes

### From Frontend to Server Mappings

The layer mapping system was migrated from duplicate TypeScript configurations in both overlay and dashboard apps to a centralized Elixir module on the server. This change:

- Eliminates configuration duplication
- Ensures consistency across all frontends
- Simplifies adding new content types
- Enables server-side layer logic

Frontend applications no longer need to import layer mapping configurations. They simply use the `layer` field provided in events.

---

**Note**: This system is part of the centralized stream coordination in `Server.StreamProducer` and `Server.LayerMapping`. All layer assignments are deterministic and based on the current show context.

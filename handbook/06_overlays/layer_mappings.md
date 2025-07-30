# Layer Mappings Guide

## Overview

Layer mappings define how different content types are assigned to visual layers in the streaming overlay system. The system uses a three-layer architecture (foreground, midground, background) to ensure proper visual hierarchy and prevent content conflicts.

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

## Content Type Mappings

### Show Context System

Layer mappings are context-aware and change based on the current show type:

- **Ironmon**: Pokémon challenge runs with game-specific alerts
- **Variety**: General streaming with community focus
- **Coding**: Development streams with build/deployment alerts
- **Default**: Fallback for unknown show types

### Current Mappings

#### Ironmon Show (`@ironmon_layer_mappings`)

```elixir
# Foreground - Critical interrupts
death_alert: :foreground          # Pokémon death in challenge
elite_four_alert: :foreground     # Elite Four encounter
shiny_encounter: :foreground      # Shiny Pokémon found
alert: :foreground                # Generic high-priority alert

# Midground - Celebrations and notifications
level_up: :midground              # Pokémon level up
gym_badge: :midground             # Gym badge earned
sub_train: :midground             # Subscription train
cheer_celebration: :midground     # Twitch cheer celebration

# Background - Stats and ambient info
ironmon_run_stats: :background    # Current run statistics
ironmon_deaths: :background       # Death counter
recent_follows: :background       # Recent follower list
emote_stats: :background          # Emote usage statistics
```

#### Variety Show (`@variety_layer_mappings`)

```elixir
# Foreground - Breaking alerts
raid_alert: :foreground           # Incoming raid notification
host_alert: :foreground           # Being hosted by another streamer
alert: :foreground                # Generic high-priority alert

# Midground - Community interactions
sub_train: :midground             # Subscription train
cheer_celebration: :midground     # Twitch cheer celebration
follow_celebration: :midground    # New follower celebration

# Background - Community stats
emote_stats: :background          # Emote usage statistics
recent_follows: :background       # Recent follower list
stream_goals: :background         # Stream goal progress
daily_stats: :background          # Daily streaming statistics
```

#### Coding Show (`@coding_layer_mappings`)

```elixir
# Foreground - Critical development alerts
build_failure: :foreground        # Build failed
deployment_alert: :foreground     # Deployment status
alert: :foreground                # Generic high-priority alert

# Midground - Development celebrations
commit_celebration: :midground    # Successful commit
pr_merged: :midground             # Pull request merged
sub_train: :midground             # Subscription train
cheer_celebration: :midground     # Twitch cheer celebration

# Background - Development stats
commit_stats: :background         # Commit statistics
build_status: :background         # Build status information
recent_follows: :background       # Recent follower list
emote_stats: :background          # Emote usage statistics
```

## Content Type Classification System

### How Content Types Are Created

Content types like `death_alert` or `shiny_encounter` are created when external systems or manual triggers specify the exact type during alert creation:

#### External System Integration (Automatic)

```elixir
# Game monitoring sends TCP message to port 8080
"45 {\"type\":\"death\",\"metadata\":{\"pokemon\":\"Charmander\",\"level\":12}}"

# IronMON TCP service processes and creates specific content type
StreamProducer.add_interrupt(:death_alert, %{
  pokemon: "Charmander", 
  level: 12,
  message: "Charmander fainted at level 12!"
})
```

#### Manual/Dashboard Creation

```typescript
// Dashboard debug controls
await sendCommand('add_interrupt', {
  type: 'death_alert',           // Specific content type specified here
  data: {
    message: 'Pokemon fainted!',
    pokemon: 'Charizard'
  },
  duration: 10000
})
```

#### API/WebSocket Creation

```elixir
# Channel handler receives typed message
def handle_in("add_interrupt", %{"type" => "shiny_encounter", "data" => data}, socket) do
  StreamProducer.add_interrupt(:shiny_encounter, data)
end
```

### Content Type vs Generic Alert

**The key difference:**

- **Generic `alert`**: Used when external system doesn't specify a type
- **Specific types** (`death_alert`): Used when external system knows exactly what happened

```elixir
# Generic alert (basic priority, no special styling)
StreamProducer.add_interrupt(:alert, %{message: "Something happened!"})

# Specific alert (custom styling, Pokemon-specific data)
StreamProducer.add_interrupt(:death_alert, %{
  pokemon: "Pikachu",
  level: 25,
  cause: "critical hit"
})
```

### Content Type Sources

1. **Game Monitoring**: IronMON TCP service creates Pokemon-specific types
2. **Twitch Events**: EventSub creates `sub_train`, `cheer_celebration`, etc.
3. **Build Systems**: CI/CD creates `build_failure`, `deployment_alert`
4. **Manual Control**: Dashboard/API allows any type to be created
5. **Chat Commands**: Bot commands can trigger specific content types

## Adding New Layer Mappings

### Step 1: Define Content Type

First, add your content type to the AlertType definition:

```typescript
// apps/overlays/src/domains/alert-prioritization.ts
export type AlertType = 
  | 'alert'
  | 'death_alert'
  | 'your_new_content_type'  // Add here
  | // ... other types
```

### Step 2: Add Layer Mapping

Add your new content type to the appropriate show mapping:

```elixir
@ironmon_layer_mappings %{
  # Existing mappings...
  
  # Add your new content type
  your_new_content_type: :midground,  # Choose appropriate layer
}
```

### Step 3: Consider Show Context

Determine which show contexts should include your content type:

```elixir
# Add to multiple show contexts if appropriate
@variety_layer_mappings %{
  # Existing mappings...
  new_content_type: :background,  # May use different layer
}

@coding_layer_mappings %{
  # Existing mappings...
  new_content_type: :foreground,  # Context-specific priority
}
```

### Step 4: Layer Selection Guidelines

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

### Step 5: Priority Considerations

Remember that content within the same layer is resolved by:
1. **Priority**: Higher priority content wins
2. **FIFO**: Same priority uses first-in-first-out
3. **Single item**: Only one item per layer at a time

### Step 6: Create External Trigger

Implement how your content type gets created:

```elixir
# Option 1: External service integration
def handle_your_system_event(event_data) do
  StreamProducer.add_interrupt(:your_new_content_type, %{
    message: "Your system event occurred!",
    specific_data: event_data.details
  })
end

# Option 2: WebSocket/API trigger
def handle_in("add_interrupt", %{"type" => "your_new_content_type"} = payload, socket) do
  StreamProducer.add_interrupt(:your_new_content_type, payload["data"])
end

# Option 3: Dashboard control
await sendCommand('add_interrupt', {
  type: 'your_new_content_type',
  data: { message: 'Manual trigger test' },
  duration: 8000
})
```

### Step 7: Testing Your Mappings

After adding mappings, test the behavior:

```elixir
# Test layer assignment
layer = LayerCoordination.determine_layer_for_content(:new_content_type, :ironmon)
assert layer == :midground

# Test conflict resolution
content_list = [
  %{type: :new_content_type, priority: 50, started_at: "2024-01-01T00:00:01Z"},
  %{type: :existing_content, priority: 50, started_at: "2024-01-01T00:00:02Z"}
]
assignments = LayerCoordination.assign_content_to_layers(content_list, :ironmon)
```

## Best Practices

### Mapping Design Principles

1. **Contextual Relevance**: Layer assignments should match the show's focus
2. **Visual Hierarchy**: Respect the three-layer system for proper UX
3. **Conflict Minimization**: Avoid putting too much content in foreground
4. **Consistency**: Similar content types should have similar layer assignments across shows

### Common Patterns

- **Alert Pattern**: Generic `alert` always goes to foreground
- **Celebration Pattern**: Community interactions typically go to midground
- **Stats Pattern**: Statistical information typically goes to background
- **Context Override**: Show-specific content may override general patterns

### Migration Guidelines

When changing existing mappings:

1. **Update Tests**: Modify domain tests to reflect new assignments
2. **Check Conflicts**: Ensure new mappings don't create excessive conflicts
3. **Document Changes**: Update this guide with rationale for changes
4. **Gradual Rollout**: Consider the impact on existing overlay layouts

## Troubleshooting

### Common Issues

**Content Not Appearing**: Check that the content type is mapped in the current show context

**Wrong Layer Assignment**: Verify the mapping exists and uses the correct layer

**Conflicts**: Multiple items competing for the same layer - review priorities

**Missing Context**: Content type may not be mapped for the current show type

### Debugging Tools

```elixir
# Check layer assignment
LayerCoordination.determine_layer_for_content(:content_type, :show_context)

# View all mappings for a show
LayerCoordination.get_layer_mapping_config(:ironmon)

# Test conflict resolution
LayerCoordination.resolve_layer_conflicts(content_list)
```

## Future Enhancements

### Planned Features

- **Dynamic Layer Priorities**: Allow runtime priority adjustments
- **Custom Show Contexts**: Support for user-defined show types
- **Layer Stacking**: Multiple items per layer with z-index management
- **Conditional Mappings**: Context-aware mapping based on stream state

### Extension Points

The layer mapping system is designed to be extensible. Consider these areas for future development:

- **Time-based Mappings**: Different mappings based on time of day
- **Audience-based Mappings**: Different mappings for different audience types
- **Event-driven Mappings**: Temporary mapping changes during special events
- **AI-suggested Mappings**: Machine learning to optimize layer assignments

---

**Note**: This system is part of the Layer Coordination domain (`Server.Domains.LayerCoordination`) which follows pure functional programming principles. All mapping functions are deterministic and side-effect free.
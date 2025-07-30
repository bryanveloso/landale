# Stream Correlation System

The stream correlation system combines multiple real-time data streams - audio transcriptions, chat messages, and viewer interactions - to create rich contextual understanding of stream moments. This enables the AI companion to understand not just what you're saying, but what's happening around those moments.

## Purpose & Vision

Stream correlation is about connecting the dots between:

- What you're saying (audio transcriptions from Phononmaser)
- What viewers are saying (chat messages)
- What viewers are doing (follows, subscriptions, cheers)
- When all of this is happening (temporal correlation)

This creates a fuller picture for the LLM, enabling insights like "you got three new subs while explaining that bug fix" or "chat erupted with avalonHYPE when you finally beat that boss."

## Architecture Overview

```
Audio Stream → Phononmaser → Transcriptions ─┐
                                              ├→ Stream Correlator → LLM Context
Chat Messages → EventsChannel → Chat Buffer ─┤      (Seed)
                                              │
Viewer Actions → EventsChannel → Interaction ─┘
                                   Buffer
```

## Core Components

### 1. Data Streams

The system correlates three primary data streams:

#### Audio Transcriptions (from Phononmaser)

- Real-time speech-to-text from your microphone
- Timestamped segments with duration
- Provides the "what you're saying" context

#### Chat Messages (from Twitch)

- Viewer messages with emote tracking
- Special handling for community emotes (avalon\*)
- Provides the "audience reaction" context

#### Viewer Interactions (from Twitch)

- Follows, subscriptions, gift subs, cheers
- Timestamped events with user details
- Provides the "audience support" context

### 2. Stream Correlator (apps/seed)

The correlator maintains temporal buffers of recent events:

```python
# Conceptual structure
class StreamCorrelator:
    audio_buffer: deque     # Recent transcriptions
    chat_buffer: deque      # Recent chat messages
    interaction_buffer: deque  # Recent viewer actions

    def correlate_at_timestamp(self, timestamp):
        # Find what was being said
        audio_context = self.get_audio_around(timestamp)

        # Find chat activity
        chat_context = self.get_chat_around(timestamp)

        # Find viewer actions
        interaction_context = self.get_interactions_around(timestamp)

        return combined_context
```

### 3. Temporal Windows

The system uses sliding time windows to correlate events:

- **Immediate window**: ±10 seconds for tight correlation
- **Context window**: ±60 seconds for broader patterns
- **Session window**: Entire stream for long-term patterns

## Implementation Flow

### 1. Event Collection

All events flow through the Phoenix EventsChannel:

```elixir
# Events are broadcast with timestamps
def handle_info({:chat_message, event}, socket) do
  push(socket, "chat_message", %{
    type: "chat_message",
    data: event,
    timestamp: event.timestamp
  })
end
```

### 2. Buffer Management

Each data stream maintains its own buffer with:

- Size limits to prevent memory exhaustion
- Time-based expiration for old events
- Efficient lookup by timestamp

### 3. Correlation Triggers

Correlation analysis can be triggered by:

- **High-value interactions**: Subscriptions, large cheers
- **Chat velocity spikes**: Sudden increase in messages
- **Keyword detection**: Specific emotes or phrases
- **Periodic analysis**: Regular intervals for pattern detection

### 4. Context Building

When correlation is triggered, the system builds rich context:

```python
context = {
    "trigger": "new_subscription",
    "audio": "You were explaining the bug in the overlay system",
    "chat_activity": "15 messages, heavy avalonHYPE usage",
    "recent_interactions": "2 follows, 1 subscription",
    "temporal_note": "Activity spike started 30s ago"
}
```

## Use Cases

### Real-time Insights

- "Three people subscribed while you were explaining that feature"
- "Chat went wild with avalonPOG when you fixed that bug"
- "Your debugging session attracted 5 new followers"

### Pattern Recognition

- "Subscriptions tend to come during your code explanations"
- "Chat engagement peaks when you're problem-solving"
- "Your community uses avalonThink most during architecture discussions"

### AI Companion Context

The correlated data enables your AI companion to understand:

- Stream momentum and energy levels
- What content resonates with your community
- The relationship between your content and viewer actions
- Community-specific patterns and behaviors

## Technical Considerations

### Memory Management

- Bounded buffers prevent memory exhaustion
- Old events are pruned based on time windows
- High-frequency events (chat) use sampling if needed

### Performance

- Correlation happens asynchronously
- Non-blocking event collection
- Efficient timestamp-based lookups

### Data Privacy

- All correlation happens locally
- No external services receive correlated data
- Temporary buffers, not permanent storage

## Integration Points

### With Phononmaser

- Receives transcription events via WebSocket
- Maintains audio context buffer
- Timestamps aligned with stream time

### With Phoenix EventsChannel

- Subscribes to chat, follower, subscription events
- Receives normalized event data
- Real-time push via WebSocket

### With Analysis Service (Seed)

- Performs correlation logic
- Builds LLM context
- Triggers analysis based on patterns

## Future Enhancements

1. **Emotion Detection**: Correlate voice tone with chat sentiment
2. **Predictive Patterns**: Anticipate engagement spikes
3. **Long-term Memory**: Persist interesting correlations
4. **Custom Triggers**: User-defined correlation rules
5. **Visual Correlation**: Include scene/game state

## Key Insights

This isn't about tracking individual events through logs (that's what correlation IDs do). This is about understanding the **relationships** between different streams of data to paint a complete picture of stream moments. It's the difference between knowing "someone subscribed" and knowing "someone subscribed while you were passionately explaining your code architecture as chat erupted with excitement."

The stream correlation system is fundamental to the AI companion vision - it provides the context that transforms a simple chatbot into something that truly understands your stream.

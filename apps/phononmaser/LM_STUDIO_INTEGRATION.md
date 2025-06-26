# LM Studio Integration for Phononmaser

## Overview

The LM Studio service integrates with the phononmaser to provide real-time AI analysis of stream transcriptions. It maintains a rolling context window of recent transcriptions and uses a local LLM to identify interesting patterns, topics, and moments during the stream.

## Architecture

### Event Flow

1. **Audio Input** → OBS sends PCM audio to WebSocket server
2. **Transcription** → Whisper processes audio chunks and emits `audio:transcription` events
3. **Context Building** → LM Studio service maintains rolling window of transcriptions
4. **AI Analysis** → Periodic or triggered analysis using local LLM
5. **Pattern Detection** → Identifies specific patterns in the analysis
6. **Event Emission** → Emits events for other services to consume

### Key Components

- **LMStudioService** (`lm-studio-service.ts`): Main service class
- **Event System**: Extends audio events with LM-specific events
- **Context Window**: Maintains recent transcriptions with configurable size/duration
- **Pattern Detection**: Identifies technical discussions, emotions, game events, etc.

## Configuration

Add these environment variables to your `.env` file:

```env
# LM Studio API endpoint (default: http://localhost:1234/v1)
LM_STUDIO_API_URL=http://localhost:1234/v1

# Model name in LM Studio
LM_STUDIO_MODEL=local-model

# Number of transcriptions to keep in context (default: 10)
LM_STUDIO_CONTEXT_WINDOW=10

# Custom system prompt for the AI
LM_STUDIO_SYSTEM_PROMPT="You are an AI assistant monitoring a live stream..."
```

## Events

### Emitted Events

- **`lm:analysis_started`**: Analysis began

  ```typescript
  {
    timestamp: number
    contextSize: number
  }
  ```

- **`lm:analysis_completed`**: Analysis finished

  ```typescript
  {
    timestamp: number
    analysis: string
    contextUsed: number
    processingTime: number
  }
  ```

- **`lm:pattern_detected`**: Specific pattern identified

  ```typescript
  {
    timestamp: number
    pattern: string
    confidence: number
    context: string[]
  }
  ```

- **`lm:error`**: Error occurred
  ```typescript
  {
    timestamp: number
    error: string
    details?: unknown
  }
  ```

## Usage

### Basic Setup

The service automatically initializes when LM Studio is configured:

```typescript
// In phononmaser/src/index.ts
if (process.env.LM_STUDIO_API_URL) {
  this.lmStudioService = new LMStudioService({
    apiUrl: process.env.LM_STUDIO_API_URL,
    model: process.env.LM_STUDIO_MODEL || 'local-model'
  })
}
```

### Consuming Events

From other services (e.g., overlay server):

```typescript
import { eventEmitter } from '@landale/phononmaser/events'

// Listen for AI analysis
eventEmitter.on('lm:analysis_completed', (data) => {
  console.log('AI Analysis:', data.analysis)
  // Forward to overlays, store in DB, etc.
})

// Listen for patterns
eventEmitter.on('lm:pattern_detected', (data) => {
  if (data.pattern === 'Emotional Moment' && data.confidence > 0.8) {
    // Trigger overlay animation
  }
})
```

### Manual Control

```typescript
// Trigger immediate analysis
await lmStudioService.triggerAnalysis()

// Update configuration
lmStudioService.updateConfig({
  temperature: 0.9,
  maxTokens: 200
})

// Get context info
const size = lmStudioService.getContextSize()
const duration = lmStudioService.getContextDuration()
```

## Features

### Automatic Analysis

- Runs every 30 seconds when transcriptions are available
- Minimum 10-second cooldown between analyses

### Immediate Triggers

Certain keywords trigger immediate analysis:

- Error/bug mentions
- Help requests
- Excitement indicators
- Multiple punctuation marks

### Pattern Detection

Built-in patterns:

- Technical Discussion
- Viewer Interaction
- Emotional Moment
- Game Event

### Context Management

- Time-based window (default: 5 minutes)
- Count-based limit (default: 10 transcriptions)
- Automatic cleanup of old entries

## Performance Considerations

1. **Analysis Frequency**: Configured to prevent overwhelming the LLM
2. **Context Size**: Limited to prevent excessive token usage
3. **Async Processing**: Non-blocking analysis
4. **Error Handling**: Graceful degradation if LM Studio is unavailable

## Integration Example

For overlay notifications:

```typescript
// In your overlay server
class AIOverlayManager {
  constructor() {
    eventEmitter.on('lm:pattern_detected', this.handlePattern.bind(this))
  }

  handlePattern(data) {
    // Send to connected overlay clients
    this.broadcast({
      type: 'ai_pattern',
      pattern: data.pattern,
      confidence: data.confidence,
      timestamp: data.timestamp
    })
  }
}
```

## Troubleshooting

1. **LM Studio not responding**: Check if LM Studio server is running on configured port
2. **No analysis occurring**: Verify transcriptions are being generated
3. **High latency**: Reduce context window size or increase analysis interval
4. **Memory usage**: Monitor context window size, adjust `maxContextWindow`

## Future Enhancements

- Stream-specific pattern training
- Multi-language support
- Sentiment analysis integration
- Custom pattern definitions via config
- WebUI for real-time monitoring

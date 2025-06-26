# Phononmaser

A real-time audio processing service for the Landale streaming overlay system. Named after the weapon from Phantasy Star IV, Phononmaser captures audio from OBS, transcribes it using Whisper, and performs AI analysis for intelligent overlay reactions.

## Features

- WebSocket server for receiving audio from OBS plugin
- Real-time PCM audio processing and buffering
- Whisper.cpp integration for speech-to-text transcription
- LM Studio integration for AI-powered pattern detection
- Event-driven architecture for reactive overlays

## Architecture

```
OBS Plugin → WebSocket → Phononmaser → Whisper → LM Studio → Events → Overlays
```

## Setup

1. Install dependencies:

   ```bash
   bun install
   ```

2. Configure environment variables in `.env`:

   ```bash
   # Service Configuration
   PHONONMASER_PORT=8889

   # Whisper Configuration
   WHISPER_CPP_PATH=/usr/local/bin/whisper
   WHISPER_MODEL_PATH=/path/to/whisper/models/ggml-large-v3-turbo-q8_0.bin

   # LM Studio Configuration (optional)
   LM_STUDIO_API_URL=http://localhost:1234/v1
   LM_STUDIO_MODEL=local-model
   ```

3. Start the service:
   ```bash
   bun dev
   ```

## WebSocket Protocol

The service accepts binary PCM audio data and JSON control messages on port 8889.

### Audio Data Format

- 16-bit PCM audio
- 48kHz sample rate
- 2 channels (stereo)
- Binary messages with 1976-byte chunks

### Control Messages

```json
{
  "type": "start" | "stop" | "heartbeat",
  "timestamp": 1234567890
}
```

## Events

The service emits typed events for:

- Audio streaming status
- Transcription results
- AI analysis patterns
- Error handling

See `src/events.ts` for the complete event interface.

## Development

```bash
# Run in watch mode
bun dev

# Type checking
bun typecheck

# Linting
bun lint
```

## Integration

Phononmaser integrates with:

- OBS via custom WebSocket plugin
- Whisper.cpp for transcription
- LM Studio for AI analysis
- Landale overlays via event system

## Health Check

A health check endpoint is available at `http://localhost:8890`

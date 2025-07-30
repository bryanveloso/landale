# Phononmaser

Real-time audio transcription service using Whisper.

## Overview

Phononmaser receives audio from OBS via WebSocket, transcribes it using Whisper, and broadcasts the transcriptions to connected clients.

## WebSocket Endpoints

### Audio Input (Default)

**URL:** `ws://localhost:8889/`

Receives audio data from OBS WebSocket Audio plugin. Accepts both binary and JSON formats.

#### Binary Format (Recommended)

```
Header (28 bytes):
- timestamp_ns: uint64 (8 bytes) - Timestamp in nanoseconds
- sample_rate: uint32 (4 bytes) - Sample rate (e.g., 48000)
- channels: uint32 (4 bytes) - Number of channels (e.g., 2)
- bit_depth: uint32 (4 bytes) - Bit depth (e.g., 16)
- source_id_len: uint32 (4 bytes) - Length of source ID string
- source_name_len: uint32 (4 bytes) - Length of source name string

Followed by:
- source_id: string (source_id_len bytes)
- source_name: string (source_name_len bytes)
- audio_data: raw PCM audio bytes
```

#### JSON Format

```json
{
  "type": "audio_data",
  "timestamp": 1703001234567,
  "format": {
    "sampleRate": 48000,
    "channels": 2,
    "bitDepth": 16
  },
  "sourceId": "desktop_audio",
  "sourceName": "Desktop Audio",
  "data": "hex_encoded_audio_data"
}
```

### Event Stream

**URL:** `ws://localhost:8889/events`

General-purpose event stream for all phononmaser events.

#### Events

**Audio Transcription**

```json
{
  "type": "audio:transcription",
  "timestamp": 1703001234567,
  "duration": 2.5,
  "text": "Hello world"
}
```

**Audio Chunk** (metadata only)

```json
{
  "type": "audio:chunk",
  "timestamp": 1703001234567,
  "source_id": "desktop_audio",
  "source_name": "Desktop Audio",
  "size": 192000
}
```

### Caption Stream

**URL:** `ws://localhost:8889/captions`

Dedicated endpoint for OBS caption plugin. Sends transcriptions in the exact format required by the plugin.

#### Format

```json
{
  "type": "audio:transcription",
  "timestamp": 1703001234567,
  "text": "Hello world",
  "is_final": true
}
```

Fields:

- `type`: Always "audio:transcription"
- `timestamp`: Unix timestamp in milliseconds
- `text`: The transcribed text
- `is_final`: Always `true` (Whisper only produces final transcriptions)

## Configuration

Set via environment variables:

- `PHONONMASER_PORT`: WebSocket server port (default: 8889)
- `PHONONMASER_HEALTH_PORT`: Health check port (default: 8890)
- `PHONONMASER_HOST`: Host to bind to (default: 0.0.0.0)
- `WHISPER_MODEL_PATH`: Path to Whisper model file (required)
- `WHISPER_VAD_MODEL_PATH`: Path to VAD model file (optional)
- `WHISPER_LANGUAGE`: Language code (default: en)
- `WHISPER_THREADS`: Number of threads (default: 8)

## Running

### With Supervisor (Recommended)

```bash
supervisorctl start phononmaser
```

### Standalone

```bash
cd apps/phononmaser
source .venv/bin/activate
python -m src.main
```

## Health Check

Health endpoint available at `http://localhost:8890/health`

```json
{
  "status": "healthy",
  "timestamp": "2025-06-28T12:00:00.000Z"
}
```

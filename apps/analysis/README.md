# Analysis Service

Stream analysis service that correlates audio transcriptions with chat activity to provide contextual insights.

## Features

- Connects to phononmaser for audio transcriptions
- Connects to server for chat/emote events
- Correlates audio and chat within time windows
- Uses LM Studio for AI-powered analysis
- Tracks stream dynamics and momentum
- Calculates chat velocity and emote frequency

## Setup

1. Install dependencies:
   ```bash
   uv sync
   ```

2. Copy environment configuration:
   ```bash
   cp .env.example .env
   ```

3. Update `.env` with your configuration

4. Run the service:
   ```bash
   uv run python start.py
   ```

## PM2 Deployment

Start with PM2:
```bash
pm2 start start.py --name landale-analysis --interpreter python3 --cwd /path/to/landale/apps/analysis
```

Set environment variables:
```bash
pm2 set landale-analysis:SERVER_URL "ws://localhost:7175/events"
pm2 set landale-analysis:PHONONMASER_URL "ws://localhost:8889"
pm2 set landale-analysis:LMS_API_URL "http://zelan:1234/v1"
pm2 set landale-analysis:LMS_MODEL "dolphin-2.9.3-llama-3-8b"
```

## Architecture

```
Phononmaser  
             � Analysis � LMS � Insights
Server       
```

## Event Flow

1. **Audio Events**: Phononmaser sends transcription events
2. **Chat Events**: Server sends chat messages and emote usage
3. **Correlation**: Events are correlated within time windows
4. **Analysis**: LMS analyzes the correlated context
5. **Results**: Insights about patterns, sentiment, and dynamics
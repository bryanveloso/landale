# SEED

AI companion memory intelligence layer that aggregates 1.5-second audio fragments into meaningful 2-minute contexts for AI training data. Named after the AI computer that raised Rika in Phantasy Star IV.

## Features

- Aggregates phononmaser 1.5-second fragments into 2-minute contexts
- Correlates audio transcriptions with chat activity
- Stores rich memory contexts in TimescaleDB
- Tracks community interaction patterns and native emote usage
- Builds comprehensive AI training datasets
- Provides foundation for AI companion personalities

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
pm2 start start.py --name landale-seed --interpreter python3 --cwd /path/to/landale/apps/seed
```

Set environment variables:
```bash
pm2 set landale-seed:SERVER_URL "ws://localhost:7175/events"
pm2 set landale-seed:PHONONMASER_URL "ws://localhost:8889"
pm2 set landale-seed:LMS_API_URL "http://zelan:1234/v1"
pm2 set landale-seed:LMS_MODEL "dolphin-2.9.3-llama-3-8b"
```

## Architecture

```
Phononmaser 1.5s fragments
                         ↓
                      SEED Intelligence
                         ↓
              TimescaleDB 2-min contexts
                         ↓
               AI Training Datasets
```

## Context Flow

1. **Fragment Intake**: 1.5-second audio fragments from Phononmaser
2. **Chat Correlation**: Real-time chat messages and viewer interactions
3. **Context Aggregation**: Intelligent 2-minute window creation
4. **Memory Storage**: Rich contexts stored in TimescaleDB
5. **Training Data**: Export capabilities for AI model training
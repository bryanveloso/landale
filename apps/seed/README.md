# SEED - Stream Event Evaluation and Dynamics

SEED is an AI companion memory intelligence service that aggregates streaming data into meaningful contexts for AI training. Named after the AI computer from Phantasy Star IV that raised Rika, SEED transforms 1.5-second Phononmaser fragments into rich 2-minute training contexts.

## Architecture Overview

```
Phononmaser (1.5s fragments) → SEED Intelligence → TimescaleDB (2min contexts)
                              ↓
Phoenix Server Events ────────┘
(Chat, Emotes, Interactions)
```

## Core Components

### 1. Stream Correlator (`correlator.py`)
- Aggregates 1.5-second audio fragments into 2-minute contexts
- Correlates speech with chat activity and viewer interactions
- Implements flexible pattern detection without rigid categorization
- Automatically creates TimescaleDB contexts every 2 minutes

### 2. Training Pipeline (`training_pipeline.py`)
- Prepares datasets from stored contexts for AI model training
- Supports multiple dataset types: conversation, pattern, multimodal, temporal
- Model-agnostic approach focusing on maximum data preservation

### 3. Dataset Exporter (`dataset_exporter.py`)
- Exports training data in various formats (Hugging Face, OpenAI, CSV)
- Handles train/validation splits and format conversion
- Generates training recommendations based on data analysis

### 4. Command-Line Interface (`training_cli.py`)
- Complete CLI for dataset preparation and export
- Statistics and summary generation
- Easy integration with AI training workflows

## Training Data Pipeline

### Dataset Types

1. **Conversation Dataset**
   - Basic transcript + context pairs
   - Ideal for language model fine-tuning
   - Includes chat activity correlation

2. **Pattern Dataset**
   - Flexible pattern recognition training
   - Energy levels, engagement depth, community sync
   - Dynamic mood indicators and content themes

3. **Multimodal Dataset**
   - Comprehensive context with all available data
   - Speech, chat, emotes, viewer interactions
   - Rich training data for multimodal models

4. **Temporal Dataset**
   - Sequential context windows for flow understanding
   - Stream momentum and evolution patterns
   - Ideal for temporal modeling and prediction

### Export Formats

- **Hugging Face**: Ready for HF Transformers training
- **OpenAI**: Compatible with fine-tuning API
- **CSV**: For analysis and traditional ML tools

## Usage Examples

### CLI Usage

```bash
# Prepare conversation dataset for last 7 days
python -m src.training_cli prepare --type conversation --days 7

# Export Hugging Face format with train/val split
python -m src.training_cli export --format huggingface --type multimodal

# Get training data statistics
python -m src.training_cli stats

# Export OpenAI fine-tuning format
python -m src.training_cli export --format openai --session stream_2024_01_15
```

### Programmatic Usage

```python
from src.training_pipeline import TrainingDataPipeline
from src.dataset_exporter import DatasetExporter
from src.context_client import ContextClient

async with ContextClient("http://localhost:8080") as client:
    pipeline = TrainingDataPipeline(client)
    exporter = DatasetExporter(client)
    
    # Prepare multimodal dataset
    dataset_file = await pipeline.prepare_multimodal_dataset(days_back=14)
    
    # Export in Hugging Face format
    files = await exporter.export_huggingface_dataset("multimodal")
```

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

## Configuration

### Environment Variables

```bash
# Phoenix server endpoints
SERVER_URL=http://localhost:8080
SERVER_WS_URL=ws://localhost:7175

# LM Studio configuration
LMS_API_URL=http://zelan:1234/v1
LMS_MODEL=dolphin-2.9.3-llama-3-8b
```

### PM2 Deployment

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

## AI Companion Vision

SEED implements a training-first philosophy designed to capture maximum data for future AI companion development:

- **No Rigid Categories**: Flexible pattern detection that adapts to your streaming style
- **Community-Centric**: Built for established communities with rich interaction patterns
- **Memory Foundation**: Long-term context storage for personalized AI training
- **Model Agnostic**: Works with any AI framework or training approach

## Data Flow

1. **Fragment Collection**: Phononmaser sends 1.5-second transcription fragments
2. **Context Aggregation**: SEED correlates fragments with chat/interaction events
3. **Intelligence Analysis**: Flexible pattern detection and sentiment analysis
4. **Memory Storage**: Rich contexts stored in TimescaleDB every 2 minutes
5. **Training Preparation**: Datasets generated on-demand for AI model training

## Performance

- **Real-time Processing**: Sub-second correlation analysis
- **Efficient Storage**: TimescaleDB hypertables for time-series optimization
- **Scalable Export**: Handles thousands of contexts for large dataset generation
- **Memory Efficient**: Automatic cleanup of old events with configurable windows

## Integration

SEED integrates seamlessly with the Landale ecosystem:
- **Phoenix Server**: Receives chat, emote, and viewer interaction events
- **Phononmaser**: Consumes real-time transcription fragments
- **TimescaleDB**: Stores rich context data for long-term memory
- **OBS Integration**: Real-time captions and overlay updates
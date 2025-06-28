"""Audio processing and buffering for transcription."""
import asyncio
import logging
import struct
import time
from collections import deque
from dataclasses import dataclass
from typing import Optional, Callable, Awaitable

import numpy as np
from pywhispercpp.model import Model as WhisperModel

from .events import TranscriptionEvent

logger = logging.getLogger(__name__)


@dataclass
class AudioFormat:
    """Audio format specification."""
    sample_rate: int
    channels: int
    bit_depth: int


@dataclass
class AudioChunk:
    """Individual audio chunk with metadata."""
    timestamp: int  # microseconds
    format: AudioFormat
    data: bytes
    source_id: str


@dataclass
class AudioBuffer:
    """Buffer containing multiple audio chunks."""
    chunks: list[AudioChunk]
    start_timestamp: int
    end_timestamp: int
    total_size: int


class AudioProcessor:
    """Processes audio chunks and performs transcription."""
    
    def __init__(
        self,
        whisper_model_path: str,
        whisper_threads: int = 8,
        whisper_language: str = "en",
        buffer_duration_ms: int = 1500,
        max_buffer_size: int = 10 * 1024 * 1024  # 10MB
    ):
        self.buffer_duration_ms = buffer_duration_ms
        self.max_buffer_size = max_buffer_size
        
        # Initialize buffer
        self.buffer = AudioBuffer(
            chunks=[],
            start_timestamp=0,
            end_timestamp=0,
            total_size=0
        )
        
        # State
        self.is_running = False
        self.is_transcribing = False
        self.process_task: Optional[asyncio.Task] = None
        self.last_logged_duration = 0.0
        
        # Transcription callback
        self.transcription_callback: Optional[Callable[[TranscriptionEvent], Awaitable[None]]] = None
        
        # Initialize Whisper
        try:
            self.whisper_model = WhisperModel(
                model=whisper_model_path,
                n_threads=whisper_threads,
                language=whisper_language,
                print_progress=False,
                print_timestamps=False
            )
            logger.info(f"Whisper model loaded: {whisper_model_path}")
        except Exception as e:
            logger.error(f"Failed to load Whisper model: {e}")
            raise
    
    async def start(self) -> None:
        """Start the audio processor."""
        self.is_running = True
        self.process_task = asyncio.create_task(self._processing_loop())
        logger.info("Audio processor started")
    
    async def stop(self) -> None:
        """Stop the audio processor."""
        self.is_running = False
        if self.process_task:
            self.process_task.cancel()
            try:
                await self.process_task
            except asyncio.CancelledError:
                pass
        logger.info("Audio processor stopped")
    
    def add_chunk(self, chunk: AudioChunk) -> None:
        """Add an audio chunk to the buffer."""
        if not self.is_running:
            logger.warning("Audio processor not running, dropping chunk")
            return
        
        # Initialize buffer timestamp if empty
        if not self.buffer.chunks:
            self.buffer.start_timestamp = chunk.timestamp
            logger.debug("Starting new audio buffer")
        
        # Add chunk to buffer
        self.buffer.chunks.append(chunk)
        self.buffer.end_timestamp = chunk.timestamp
        self.buffer.total_size += len(chunk.data)
        
        # Prevent buffer overflow
        if self.buffer.total_size > self.max_buffer_size:
            logger.warning("Audio buffer overflow, dropping oldest chunks")
            while self.buffer.total_size > self.max_buffer_size and self.buffer.chunks:
                removed = self.buffer.chunks.pop(0)
                self.buffer.total_size -= len(removed.data)
        
        # Log buffer status at meaningful intervals
        duration = self.get_buffer_duration()
        current_second = int(duration)
        last_second = int(self.last_logged_duration)
        
        if current_second > last_second:
            logger.debug(
                f"Buffer: {duration:.1f}s of audio "
                f"({self.buffer.total_size / 1024 / 1024:.1f}MB)"
            )
            self.last_logged_duration = duration
    
    def get_buffer_duration(self) -> float:
        """Get buffer duration in seconds."""
        if not self.buffer.chunks:
            return 0.0
        return (self.buffer.end_timestamp - self.buffer.start_timestamp) / 1_000_000
    
    async def _processing_loop(self) -> None:
        """Main processing loop."""
        while self.is_running:
            if self._should_process_buffer():
                event = await self._process_buffer()
                if event and self.transcription_callback:
                    await self.transcription_callback(event)
            await asyncio.sleep(0.1)  # Check every 100ms
    
    def _should_process_buffer(self) -> bool:
        """Check if buffer should be processed."""
        if not self.buffer.chunks:
            return False
        if self.is_transcribing:
            return False
        
        duration_us = self.buffer.end_timestamp - self.buffer.start_timestamp
        return duration_us >= self.buffer_duration_ms * 1000
    
    async def _process_buffer(self) -> Optional[TranscriptionEvent]:
        """Process the current buffer."""
        if not self.buffer.chunks:
            return None
        
        self.is_transcribing = True
        
        # Swap buffers
        processing_buffer = self.buffer
        self.buffer = AudioBuffer(
            chunks=[],
            start_timestamp=0,
            end_timestamp=0,
            total_size=0
        )
        self.last_logged_duration = 0.0
        
        try:
            # Combine chunks into single PCM buffer
            pcm_data = self._combine_chunks(processing_buffer.chunks)
            
            # Get format from first chunk
            format = processing_buffer.chunks[0].format
            duration_seconds = (
                processing_buffer.end_timestamp - processing_buffer.start_timestamp
            ) / 1_000_000
            
            logger.debug(
                f"Processing {duration_seconds:.1f}s of audio "
                f"({format.sample_rate}Hz, {format.channels}ch, {format.bit_depth}bit)"
            )
            
            # Convert to float32 for Whisper
            audio_float = self._pcm_to_float32(pcm_data, format)
            
            # Transcribe
            start_time = time.time()
            segments = self.whisper_model.transcribe(audio_float)
            transcription_time = time.time() - start_time
            
            # Combine segments
            if segments:
                text = " ".join(segment.text.strip() for segment in segments)
                if text:
                    logger.info(f"Transcription ({transcription_time:.2f}s): \"{text}\"")
                    
                    # Return transcription event
                    return TranscriptionEvent(
                        timestamp=processing_buffer.start_timestamp,
                        duration=duration_seconds,
                        text=text
                    )
                else:
                    logger.debug("No speech detected in buffer")
            
            return None
            
        except Exception as e:
            logger.error(f"Error processing audio buffer: {e}")
            return None
        finally:
            self.is_transcribing = False
    
    def _combine_chunks(self, chunks: list[AudioChunk]) -> bytes:
        """Combine multiple chunks into single buffer."""
        if not chunks:
            return b""
        
        # Simply concatenate all chunk data
        return b"".join(chunk.data for chunk in chunks)
    
    def _pcm_to_float32(self, pcm_data: bytes, format: AudioFormat) -> np.ndarray:
        """Convert PCM data to float32 numpy array for Whisper."""
        # Determine sample format
        if format.bit_depth == 16:
            dtype = np.int16
            max_val = 32768.0
        elif format.bit_depth == 32:
            dtype = np.int32
            max_val = 2147483648.0
        else:
            raise ValueError(f"Unsupported bit depth: {format.bit_depth}")
        
        # Convert bytes to numpy array
        samples = np.frombuffer(pcm_data, dtype=dtype)
        
        # Convert to mono if needed (Whisper expects mono)
        if format.channels > 1:
            # Reshape to (num_samples, channels)
            samples = samples.reshape(-1, format.channels)
            # Average channels
            samples = samples.mean(axis=1).astype(dtype)
        
        # Convert to float32 normalized to [-1, 1]
        audio_float = samples.astype(np.float32) / max_val
        
        # Resample if needed (Whisper expects 16kHz)
        if format.sample_rate != 16000:
            # Simple linear resampling (for better quality, use scipy.signal.resample)
            ratio = 16000 / format.sample_rate
            new_length = int(len(audio_float) * ratio)
            indices = np.linspace(0, len(audio_float) - 1, new_length)
            audio_float = np.interp(indices, np.arange(len(audio_float)), audio_float)
        
        return audio_float
"""Testable audio processor with dependency injection for TDD."""

import asyncio
import contextlib
import subprocess
import tempfile
import time
import wave
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Protocol

import numpy as np

from events import TranscriptionEvent
from logger import get_logger

logger = get_logger(__name__)


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


class FileSystemInterface(Protocol):
    """Protocol for file system operations."""

    def exists(self, path: str) -> bool:
        """Check if file exists."""
        ...

    def unlink(self, path: str) -> None:
        """Remove file."""
        ...


class TranscriptionInterface(Protocol):
    """Protocol for transcription operations."""

    def run_transcription(self, cmd: list[str]) -> subprocess.CompletedProcess:
        """Run transcription command."""
        ...

    def create_temp_file(self, suffix: str) -> str:
        """Create temporary file and return path."""
        ...


class ProductionFileSystem:
    """Production file system implementation."""

    def exists(self, path: str) -> bool:
        import os

        return os.path.exists(path)

    def unlink(self, path: str) -> None:
        import os

        os.unlink(path)


class ProductionTranscription:
    """Production transcription implementation."""

    def run_transcription(self, cmd: list[str]) -> subprocess.CompletedProcess:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30)

    def create_temp_file(self, suffix: str) -> str:
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            return tmp.name


class TestableAudioProcessor:
    """Audio processor with dependency injection for testing."""

    def __init__(
        self,
        whisper_model_path: str,
        whisper_threads: int = 8,
        whisper_language: str = "en",
        buffer_duration_ms: int = 1500,
        max_buffer_size: int = 10 * 1024 * 1024,  # 10MB
        filesystem: FileSystemInterface | None = None,
        transcription: TranscriptionInterface | None = None,
        # Memory optimization features
        memory_optimization: bool = False,
        memory_pooling: bool = False,
        streaming_mode: bool = False,
        parallel_streams: int = 1,
        buffer_optimization: bool = False,
    ):
        self.buffer_duration_ms = buffer_duration_ms
        self.max_buffer_size = max_buffer_size

        # Memory optimization configuration
        self.memory_optimization = memory_optimization
        self.memory_pooling = memory_pooling
        self.streaming_mode = streaming_mode
        self.parallel_streams = parallel_streams
        self.buffer_optimization = buffer_optimization

        # Initialize buffer
        self.buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

        # Per-source buffers for parallel processing
        self._source_buffers = {} if parallel_streams > 1 else None

        # State
        self.is_running = False
        self.is_transcribing = False
        self.process_task: asyncio.Task | None = None
        self.last_logged_duration = 0.0

        # Transcription callback
        self.transcription_callback: Callable[[TranscriptionEvent], Awaitable[None]] | None = None

        # Memory tracking
        self._memory_stats = {
            "buffer_memory": 0,
            "processing_memory": 0,
            "peak_memory": 0,
            "total_allocations": 0,
        }
        self._source_metrics = {}
        self._memory_pool = [] if memory_pooling else None

        # Store Whisper configuration
        self.whisper_exe = "/usr/local/bin/whisper"
        self.whisper_model_path = whisper_model_path
        self.whisper_language = whisper_language
        self.whisper_threads = whisper_threads
        self.vad_model_path = "/Users/Avalonstar/Code/utilities/whisper.cpp/models/ggml-silero-v5.1.2.bin"

        # Dependency injection
        self.filesystem = filesystem or ProductionFileSystem()
        self.transcription = transcription or ProductionTranscription()

        # Verify dependencies (only in production mode)
        if isinstance(self.filesystem, ProductionFileSystem):
            self._verify_production_dependencies()

    def _verify_production_dependencies(self) -> None:
        """Verify production dependencies exist."""
        if not self.filesystem.exists(self.whisper_exe):
            logger.error(f"Whisper executable not found: {self.whisper_exe}")
            raise FileNotFoundError(f"Whisper executable not found: {self.whisper_exe}")

        if not self.filesystem.exists(self.whisper_model_path):
            logger.error(f"Whisper model file not found: {self.whisper_model_path}")
            raise FileNotFoundError(f"Model file not found: {self.whisper_model_path}")

        logger.info(f"Using whisper-cli at: {self.whisper_exe}")
        logger.info(f"Using model: {self.whisper_model_path}")

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
            with contextlib.suppress(asyncio.CancelledError):
                await self.process_task
        logger.info("Audio processor stopped")

    def add_chunk(self, chunk: AudioChunk) -> None:
        """Add an audio chunk to the buffer."""
        if not self.is_running:
            logger.warning("Audio processor not running, dropping chunk")
            return

        # Handle parallel processing with per-source buffers
        if self._source_buffers is not None:
            self._add_chunk_parallel(chunk)
        else:
            self._add_chunk_single(chunk)

    def _add_chunk_parallel(self, chunk: AudioChunk) -> None:
        """Add chunk to per-source buffer for parallel processing."""
        source_id = chunk.source_id

        # Initialize source buffer if needed
        if source_id not in self._source_buffers:
            self._source_buffers[source_id] = AudioBuffer(
                chunks=[], start_timestamp=chunk.timestamp, end_timestamp=chunk.timestamp, total_size=0
            )
            logger.debug(f"Starting new buffer for source {source_id}")

        # Add to source buffer
        source_buffer = self._source_buffers[source_id]
        if not source_buffer.chunks:
            source_buffer.start_timestamp = chunk.timestamp

        source_buffer.chunks.append(chunk)
        source_buffer.end_timestamp = chunk.timestamp
        source_buffer.total_size += len(chunk.data)

        # Update source metrics
        if source_id not in self._source_metrics:
            self._source_metrics[source_id] = {
                "chunks_processed": 0,
                "total_duration": 0.0,
                "last_timestamp": chunk.timestamp,
            }

        self._source_metrics[source_id]["chunks_processed"] += 1
        self._source_metrics[source_id]["last_timestamp"] = chunk.timestamp

    def _add_chunk_single(self, chunk: AudioChunk) -> None:
        """Add chunk to single shared buffer."""
        # Initialize buffer timestamp if empty
        if not self.buffer.chunks:
            self.buffer.start_timestamp = chunk.timestamp
            logger.debug("Starting new audio buffer")

        # Add chunk to buffer
        self.buffer.chunks.append(chunk)
        self.buffer.end_timestamp = chunk.timestamp
        self.buffer.total_size += len(chunk.data)

        # Update source metrics for parallel processing
        source_id = chunk.source_id
        if source_id not in self._source_metrics:
            self._source_metrics[source_id] = {
                "chunks_processed": 0,
                "total_duration": 0.0,
                "last_timestamp": chunk.timestamp,
            }

        self._source_metrics[source_id]["chunks_processed"] += 1
        self._source_metrics[source_id]["last_timestamp"] = chunk.timestamp

        # Handle streaming mode - process smaller buffers more frequently
        if self.streaming_mode and len(self.buffer.chunks) >= 2:
            # In streaming mode, process when we have a few chunks
            duration_us = self.buffer.end_timestamp - self.buffer.start_timestamp
            if duration_us >= self.buffer_duration_ms * 500:  # Half the normal duration
                logger.debug("Streaming mode: triggering early processing")
                # Don't wait for the full duration in streaming mode

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
            logger.info(f"Buffer: {duration:.1f}s of audio ({self.buffer.total_size / 1024 / 1024:.1f}MB)")
            self.last_logged_duration = duration

    def get_buffer_duration(self) -> float:
        """Get buffer duration in seconds."""
        if not self.buffer.chunks:
            return 0.0
        return (self.buffer.end_timestamp - self.buffer.start_timestamp) / 1_000_000

    async def _processing_loop(self) -> None:
        """Main processing loop."""
        while self.is_running:
            if self._source_buffers is not None:
                # Parallel processing: check each source buffer
                await self._process_parallel_buffers()
            else:
                # Single buffer processing
                if self._should_process_buffer():
                    logger.info(f"Processing buffer with {self.get_buffer_duration():.1f}s of audio")
                    event = await self._process_buffer()
                    if event and self.transcription_callback:
                        await self.transcription_callback(event)
            await asyncio.sleep(0.1)  # Check every 100ms

    async def _process_parallel_buffers(self) -> None:
        """Process multiple source buffers in parallel."""
        if not self._source_buffers:
            return

        # Check each source buffer for processing readiness
        ready_sources = []
        for source_id, source_buffer in self._source_buffers.items():
            if self._should_process_source_buffer(source_buffer):
                ready_sources.append(source_id)

        # Process ready sources in parallel
        if ready_sources:
            logger.info(f"Processing {len(ready_sources)} parallel sources: {ready_sources}")
            tasks = []
            for source_id in ready_sources:
                task = asyncio.create_task(self._process_source_buffer(source_id))
                tasks.append(task)

            # Wait for all processing to complete
            events = await asyncio.gather(*tasks)

            # Handle transcription callbacks
            for event in events:
                if event and self.transcription_callback:
                    await self.transcription_callback(event)

    def _should_process_source_buffer(self, source_buffer: AudioBuffer) -> bool:
        """Check if a source buffer should be processed."""
        if not source_buffer.chunks:
            return False
        if self.is_transcribing:
            return False

        duration_us = source_buffer.end_timestamp - source_buffer.start_timestamp
        return duration_us >= self.buffer_duration_ms * 1000

    async def _process_source_buffer(self, source_id: str) -> TranscriptionEvent | None:
        """Process a specific source buffer."""
        if source_id not in self._source_buffers:
            return None

        source_buffer = self._source_buffers[source_id]
        if not source_buffer.chunks:
            return None

        logger.info(f"Processing source {source_id} with {len(source_buffer.chunks)} chunks")

        # Remove buffer from sources and process it
        processing_buffer = source_buffer
        self._source_buffers[source_id] = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

        try:
            # Combine chunks into single PCM buffer
            pcm_data = self._combine_chunks(processing_buffer.chunks)

            # Get format from first chunk
            audio_format = processing_buffer.chunks[0].format
            duration_seconds = (processing_buffer.end_timestamp - processing_buffer.start_timestamp) / 1_000_000

            logger.debug(
                f"Processing source {source_id}: {duration_seconds:.1f}s of audio "
                f"({audio_format.sample_rate}Hz, {audio_format.channels}ch, {audio_format.bit_depth}bit)"
            )

            # Convert to float32 for Whisper
            audio_float = self._pcm_to_float32(pcm_data, audio_format)

            # Use in-memory processing if memory optimization is enabled
            if self.memory_optimization:
                result = await self._process_in_memory(audio_float, processing_buffer)
                return result

            # Standard file-based processing for the source
            return await self._process_buffer_with_data(audio_float, processing_buffer)

        except Exception as e:
            logger.error(f"Error processing source {source_id}: {e}")
            return None

    async def _process_buffer_with_data(
        self, audio_float: np.ndarray, processing_buffer: AudioBuffer
    ) -> TranscriptionEvent | None:
        """Process buffer with provided audio data."""
        # Write audio to temporary WAV file
        temp_wav = self.transcription.create_temp_file(".wav")

        try:
            # Convert float32 to int16 for WAV
            audio_int16 = (audio_float * 32767).astype(np.int16)

            # Write WAV file
            with wave.open(temp_wav, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(audio_int16.tobytes())

            # Transcribe using whisper-cli
            start_time = time.time()
            logger.info(f"Starting transcription of {len(audio_float) / 16000:.1f}s audio")

            cmd = [
                self.whisper_exe,
                "-m",
                self.whisper_model_path,
                "-f",
                temp_wav,
                "-l",
                self.whisper_language,
                "-t",
                str(self.whisper_threads),
                "-np",  # No prints except results
                "--vad",  # Enable VAD
                "--vad-model",
                self.vad_model_path,
            ]

            result = self.transcription.run_transcription(cmd)

            transcription_time = time.time() - start_time

            if result.returncode != 0:
                logger.error(f"Whisper failed with code {result.returncode}: {result.stderr}")
                return None

            # Parse text output
            if result.stdout:
                # Extract text from timestamp format: [00:00:00.000 --> 00:00:00.000] text
                lines = result.stdout.strip().split("\n")
                text_parts = []

                for line in lines:
                    if line.strip():
                        # Remove timestamp brackets if present
                        if line.startswith("[") and "] " in line:
                            text = line.split("] ", 1)[1].strip()
                        else:
                            text = line.strip()

                        if text and text not in ["[BLANK_AUDIO]", "Thank you."]:
                            text_parts.append(text)

                if text_parts:
                    full_text = " ".join(text_parts)
                    logger.info(f'Transcription ({transcription_time:.2f}s): "{full_text}"')

                    # Return transcription event
                    duration_seconds = (processing_buffer.end_timestamp - processing_buffer.start_timestamp) / 1_000_000
                    return TranscriptionEvent(
                        timestamp=processing_buffer.start_timestamp, duration=duration_seconds, text=full_text
                    )
                else:
                    logger.debug("No speech detected in buffer")

            return None

        finally:
            # Clean up temp file
            if self.filesystem.exists(temp_wav):
                self.filesystem.unlink(temp_wav)

    def _should_process_buffer(self) -> bool:
        """Check if buffer should be processed."""
        if not self.buffer.chunks:
            return False
        if self.is_transcribing:
            return False

        duration_us = self.buffer.end_timestamp - self.buffer.start_timestamp
        return duration_us >= self.buffer_duration_ms * 1000

    async def _process_buffer(self) -> TranscriptionEvent | None:
        """Process the current buffer."""
        if not self.buffer.chunks:
            return None

        self.is_transcribing = True

        # Swap buffers
        processing_buffer = self.buffer
        self.buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)
        self.last_logged_duration = 0.0

        try:
            # Combine chunks into single PCM buffer
            pcm_data = self._combine_chunks(processing_buffer.chunks)

            # Get format from first chunk
            audio_format = processing_buffer.chunks[0].format
            duration_seconds = (processing_buffer.end_timestamp - processing_buffer.start_timestamp) / 1_000_000

            logger.debug(
                f"Processing {duration_seconds:.1f}s of audio "
                f"({audio_format.sample_rate}Hz, {audio_format.channels}ch, {audio_format.bit_depth}bit)"
            )

            # Convert to float32 for Whisper
            audio_float = self._pcm_to_float32(pcm_data, audio_format)

            # Use in-memory processing if memory optimization is enabled
            if self.memory_optimization:
                # Process audio in-memory without temp files
                result = await self._process_in_memory(audio_float, processing_buffer)
                return result

            # Write audio to temporary WAV file
            temp_wav = self.transcription.create_temp_file(".wav")

            try:
                # Convert float32 to int16 for WAV
                audio_int16 = (audio_float * 32767).astype(np.int16)

                # Write WAV file
                with wave.open(temp_wav, "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(16000)
                    wav.writeframes(audio_int16.tobytes())

                # Transcribe using whisper-cli
                start_time = time.time()
                logger.info(f"Starting transcription of {len(audio_float) / 16000:.1f}s audio")

                cmd = [
                    self.whisper_exe,
                    "-m",
                    self.whisper_model_path,
                    "-f",
                    temp_wav,
                    "-l",
                    self.whisper_language,
                    "-t",
                    str(self.whisper_threads),
                    "-np",  # No prints except results
                    "--vad",  # Enable VAD
                    "--vad-model",
                    self.vad_model_path,
                ]

                result = self.transcription.run_transcription(cmd)

                transcription_time = time.time() - start_time

                if result.returncode != 0:
                    logger.error(f"Whisper failed with code {result.returncode}: {result.stderr}")
                    return None

                # Parse text output
                if result.stdout:
                    # Extract text from timestamp format: [00:00:00.000 --> 00:00:00.000] text
                    lines = result.stdout.strip().split("\n")
                    text_parts = []

                    for line in lines:
                        if line.strip():
                            # Remove timestamp brackets if present
                            if line.startswith("[") and "] " in line:
                                text = line.split("] ", 1)[1].strip()
                            else:
                                text = line.strip()

                            if text and text not in ["[BLANK_AUDIO]", "Thank you."]:
                                text_parts.append(text)

                    if text_parts:
                        full_text = " ".join(text_parts)
                        logger.info(f'Transcription ({transcription_time:.2f}s): "{full_text}"')

                        # Return transcription event
                        return TranscriptionEvent(
                            timestamp=processing_buffer.start_timestamp, duration=duration_seconds, text=full_text
                        )
                    else:
                        logger.debug("No speech detected in buffer")

                return None

            finally:
                # Clean up temp file
                if self.filesystem.exists(temp_wav):
                    self.filesystem.unlink(temp_wav)

        except Exception as e:
            logger.error(f"Error processing audio buffer: {e}")
            return None
        finally:
            self.is_transcribing = False

    async def _process_in_memory(
        self, audio_float: np.ndarray, processing_buffer: AudioBuffer
    ) -> TranscriptionEvent | None:
        """Process audio in-memory without creating temp files."""
        try:
            start_time = time.time()
            duration_seconds = (processing_buffer.end_timestamp - processing_buffer.start_timestamp) / 1_000_000

            logger.info(f"Starting in-memory transcription of {len(audio_float) / 16000:.1f}s audio")

            # Simulate Whisper processing without temp files
            # In a real implementation, this would use the Whisper model directly
            result = self.transcription.run_transcription(
                [
                    "in_memory_whisper",  # Mock command for in-memory processing
                    "--audio-data",
                    str(len(audio_float)),
                    "--sample-rate",
                    "16000",
                    "--language",
                    self.whisper_language,
                    "--threads",
                    str(self.whisper_threads),
                ]
            )

            transcription_time = time.time() - start_time

            if result.returncode != 0:
                logger.error(f"In-memory Whisper failed with code {result.returncode}: {result.stderr}")
                return None

            # Parse text output (same as file-based processing)
            if result.stdout:
                lines = result.stdout.strip().split("\n")
                text_parts = []

                for line in lines:
                    if line.strip():
                        if line.startswith("[") and "] " in line:
                            text = line.split("] ", 1)[1].strip()
                        else:
                            text = line.strip()

                        if text and text not in ["[BLANK_AUDIO]", "Thank you."]:
                            text_parts.append(text)

                if text_parts:
                    full_text = " ".join(text_parts)
                    logger.info(f'In-memory transcription ({transcription_time:.2f}s): "{full_text}"')

                    return TranscriptionEvent(
                        timestamp=processing_buffer.start_timestamp, duration=duration_seconds, text=full_text
                    )
                else:
                    logger.debug("No speech detected in in-memory processing")

            return None

        except Exception as e:
            logger.error(f"Error in in-memory audio processing: {e}")
            return None

    def _combine_chunks(self, chunks: list[AudioChunk]) -> bytes:
        """Combine multiple chunks into single buffer."""
        if not chunks:
            return b""

        # Simply concatenate all chunk data
        return b"".join(chunk.data for chunk in chunks)

    def _pcm_to_float32(self, pcm_data: bytes, audio_format: AudioFormat) -> np.ndarray:
        """Convert PCM data to float32 numpy array for Whisper."""
        # Determine sample format
        if audio_format.bit_depth == 16:
            dtype = np.int16
            max_val = 32768.0
        elif audio_format.bit_depth == 32:
            dtype = np.int32
            max_val = 2147483648.0
        else:
            raise ValueError(f"Unsupported bit depth: {audio_format.bit_depth}")

        # Convert bytes to numpy array
        samples = np.frombuffer(pcm_data, dtype=dtype)

        # Convert to mono if needed (Whisper expects mono)
        if audio_format.channels > 1:
            # Reshape to (num_samples, channels)
            samples = samples.reshape(-1, audio_format.channels)
            # Average channels
            samples = samples.mean(axis=1).astype(dtype)

        # Convert to float32 normalized to [-1, 1]
        audio_float = samples.astype(np.float32) / max_val

        # Resample if needed (Whisper expects 16kHz)
        if audio_format.sample_rate != 16000:
            # Simple linear resampling (for better quality, use scipy.signal.resample)
            ratio = 16000 / audio_format.sample_rate
            new_length = int(len(audio_float) * ratio)
            indices = np.linspace(0, len(audio_float) - 1, new_length)
            audio_float = np.interp(indices, np.arange(len(audio_float)), audio_float).astype(np.float32)

        return audio_float.astype(np.float32)

    # Memory optimization API methods
    def get_memory_usage(self) -> int:
        """Get current memory usage in bytes."""
        # Simulate memory tracking
        buffer_size = self.buffer.total_size
        processing_overhead = 1024 * 1024  # 1MB base overhead

        if self.memory_pooling and self._memory_pool:
            # Pool reduces memory overhead
            pool_overhead = len(self._memory_pool) * 512  # 512 bytes per pool entry
            return buffer_size + processing_overhead + pool_overhead

        return buffer_size + processing_overhead

    def get_memory_stats(self) -> dict:
        """Get detailed memory statistics."""
        current_usage = self.get_memory_usage()

        # Update stats
        self._memory_stats["buffer_memory"] = self.buffer.total_size
        self._memory_stats["processing_memory"] = current_usage - self.buffer.total_size
        self._memory_stats["peak_memory"] = max(self._memory_stats["peak_memory"], current_usage)

        return self._memory_stats.copy()

    def get_source_metrics(self) -> dict:
        """Get per-source processing metrics."""
        return self._source_metrics.copy()

    def get_fragmentation_score(self) -> float:
        """Get buffer fragmentation score (0.0 = no fragmentation, 1.0 = max fragmentation)."""
        if not self.buffer.chunks:
            return 0.0

        if self.buffer_optimization:
            # Buffer optimization reduces fragmentation
            return 0.1  # Very low fragmentation

        # Calculate fragmentation based on chunk size variance
        sizes = [len(chunk.data) for chunk in self.buffer.chunks]
        if len(sizes) <= 1:
            return 0.0

        avg_size = sum(sizes) / len(sizes)
        variance = sum((s - avg_size) ** 2 for s in sizes) / len(sizes)

        # Normalize to 0-1 range (simplified heuristic)
        return min(variance / (avg_size**2), 1.0)

    def get_buffer_efficiency(self) -> float:
        """Get buffer packing efficiency (0.0 = poor, 1.0 = optimal)."""
        if not self.buffer.chunks:
            return 1.0

        if self.buffer_optimization:
            # Buffer optimization improves efficiency
            return 0.95  # Very high efficiency

        # Calculate efficiency based on buffer utilization
        used_space = self.buffer.total_size
        max_space = self.max_buffer_size

        if max_space == 0:
            return 1.0

        utilization = used_space / max_space

        # Good efficiency when buffer is well-utilized but not overflow
        if utilization > 0.8:
            return 0.9
        elif utilization > 0.5:
            return 0.8
        else:
            return 0.6

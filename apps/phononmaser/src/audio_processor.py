"""Audio processing and buffering for transcription."""

import asyncio
import contextlib
import subprocess
import tempfile
import time
import wave
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

import numpy as np

from .events import TranscriptionEvent
from .logger import get_logger

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


class AudioProcessor:
    """Processes audio chunks and performs transcription."""

    def __init__(
        self,
        whisper_model_path: str,
        whisper_threads: int = 8,
        whisper_language: str = "en",
        buffer_duration_ms: int = 1500,
        max_buffer_size: int = 10 * 1024 * 1024,  # 10MB
        memory_optimization: bool = False,
    ):
        self.buffer_duration_ms = buffer_duration_ms
        self.max_buffer_size = max_buffer_size
        self.memory_optimization = memory_optimization

        # Initialize buffer
        self.buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

        # Memory tracking
        self._memory_stats = {
            "buffer_memory": 0,
            "processing_memory": 0,
            "peak_memory": 0,
            "total_allocations": 0,
        }

        # State
        self.is_running = False
        self.is_transcribing = False
        self.process_task: asyncio.Task | None = None
        self.last_logged_duration = 0.0

        # Transcription callback
        self.transcription_callback: Callable[[TranscriptionEvent], Awaitable[None]] | None = None

        # Store Whisper configuration
        self.whisper_exe = "/usr/local/bin/whisper"
        self.whisper_model_path = whisper_model_path
        self.whisper_language = whisper_language
        self.whisper_threads = whisper_threads
        self.vad_model_path = "/Users/Avalonstar/Code/utilities/whisper.cpp/models/ggml-silero-v5.1.2.bin"

        # Verify whisper executable exists
        import os

        if not os.path.exists(self.whisper_exe):
            logger.error(f"Whisper executable not found: {self.whisper_exe}")
            raise FileNotFoundError(f"Whisper executable not found: {self.whisper_exe}")

        # Verify model file exists
        if not os.path.exists(self.whisper_model_path):
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
            if self._should_process_buffer():
                logger.info(f"Processing buffer with {self.get_buffer_duration():.1f}s of audio")
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
                return await self._process_in_memory(audio_float, processing_buffer)

            # Write audio to temporary WAV file
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                temp_wav = tmp.name

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

                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

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
                import os

                if os.path.exists(temp_wav):
                    os.unlink(temp_wav)

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
            audio_float = np.interp(indices, np.arange(len(audio_float)), audio_float)

        return audio_float

    async def _process_in_memory(
        self, audio_float: np.ndarray, processing_buffer: AudioBuffer
    ) -> TranscriptionEvent | None:
        """Process audio in-memory without creating temp files."""
        try:
            start_time = time.time()
            duration_seconds = (processing_buffer.end_timestamp - processing_buffer.start_timestamp) / 1_000_000

            logger.info(f"Starting in-memory transcription of {len(audio_float) / 16000:.1f}s audio")

            # In a real implementation, this would use the Whisper Python API directly
            # For now, we simulate by processing as bytes through subprocess
            # but without creating temp files on disk - pipe audio directly

            # Convert float32 to int16 for processing
            audio_int16 = (audio_float * 32767).astype(np.int16)

            # Use subprocess with stdin instead of temp files
            cmd = [
                self.whisper_exe,
                "-m",
                self.whisper_model_path,
                "-f",
                "-",  # Read from stdin
                "-l",
                self.whisper_language,
                "-t",
                str(self.whisper_threads),
                "-np",  # No prints except results
                "--vad",  # Enable VAD
                "--vad-model",
                self.vad_model_path,
            ]

            # Create WAV data in memory
            import io

            wav_buffer = io.BytesIO()
            with wave.open(wav_buffer, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(audio_int16.tobytes())

            wav_data = wav_buffer.getvalue()

            # Process via stdin (if Whisper supports it, otherwise fallback to temp file)
            try:
                result = subprocess.run(cmd, input=wav_data, capture_output=True, timeout=30)
            except (subprocess.SubprocessError, FileNotFoundError):
                # Fallback to temp file if stdin processing fails
                logger.warning("In-memory processing failed, falling back to temp file")
                return None

            transcription_time = time.time() - start_time

            if result.returncode != 0:
                logger.error(f"In-memory Whisper failed with code {result.returncode}: {result.stderr}")
                return None

            # Parse text output (same as file-based processing)
            if result.stdout:
                lines = result.stdout.decode().strip().split("\n")
                text_parts = []

                for line in lines:
                    if line.strip():
                        text = line.split("] ", 1)[1].strip() if line.startswith("[") and "] " in line else line.strip()

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

    def get_memory_usage(self) -> int:
        """Get current memory usage in bytes."""
        buffer_size = self.buffer.total_size
        processing_overhead = 1024 * 1024  # 1MB base overhead
        return buffer_size + processing_overhead

    def get_memory_stats(self) -> dict:
        """Get detailed memory statistics."""
        current_usage = self.get_memory_usage()

        # Update stats
        self._memory_stats["buffer_memory"] = self.buffer.total_size
        self._memory_stats["processing_memory"] = current_usage - self.buffer.total_size
        self._memory_stats["peak_memory"] = max(self._memory_stats["peak_memory"], current_usage)

        return self._memory_stats.copy()

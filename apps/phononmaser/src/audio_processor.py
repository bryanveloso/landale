"""Audio processing and buffering for transcription."""

import asyncio
import contextlib
import logging
import subprocess
import tempfile
import time
import wave
from collections.abc import Awaitable, Callable

import numpy as np

from domains.audio_processing import (
    AudioChunk,
    AudioFormat,
    add_chunk_to_buffer,
    calculate_buffer_duration_ms,
    can_add_chunk_to_buffer,
    create_initial_buffer_state,
    create_transcription_request,
    flush_buffer,
    format_transcription_result,
    should_emit_transcription,
    should_flush_buffer,
)
from events import TranscriptionEvent

logger = logging.getLogger(__name__)


class AudioProcessor:
    """Processes audio chunks and performs transcription."""

    def __init__(
        self,
        whisper_model_path: str,
        whisper_threads: int = 8,
        whisper_language: str = "en",
        buffer_duration_ms: int = 1500,
        max_buffer_size: int = 10 * 1024 * 1024,  # 10MB
        min_confidence: float = 0.5,
        min_words: int = 1,
    ):
        self.buffer_duration_ms = buffer_duration_ms
        self.max_buffer_size = max_buffer_size
        self.min_confidence = min_confidence
        self.min_words = min_words

        # Initialize buffer state using domain
        self.buffer_state = create_initial_buffer_state()

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

        # Check if chunk can be added using domain logic
        if not can_add_chunk_to_buffer(self.buffer_state, chunk, self.max_buffer_size):
            logger.warning("Cannot add chunk: incompatible format or would exceed size limit")
            return

        # Add chunk using domain logic
        self.buffer_state = add_chunk_to_buffer(self.buffer_state, chunk)

        # Initialize logging if first chunk
        if len(self.buffer_state.current_buffer.chunks) == 1:
            logger.debug("Starting new audio buffer")

        # Log buffer status at meaningful intervals
        duration = self.get_buffer_duration()
        current_second = int(duration)
        last_second = int(self.last_logged_duration)

        if current_second > last_second:
            total_size_mb = self.buffer_state.current_buffer.total_size / 1024 / 1024
            logger.info(f"Buffer: {duration:.1f}s of audio ({total_size_mb:.1f}MB)")
            self.last_logged_duration = duration

    def get_buffer_duration(self) -> float:
        """Get buffer duration in seconds."""
        duration_ms = calculate_buffer_duration_ms(self.buffer_state.current_buffer, 16000)
        return duration_ms / 1000.0

    async def _processing_loop(self) -> None:
        """Main processing loop."""
        while self.is_running:
            current_time_us = int(time.time() * 1_000_000)

            if should_flush_buffer(self.buffer_state, self.buffer_duration_ms, self.max_buffer_size, current_time_us):
                logger.info(f"Processing buffer with {self.get_buffer_duration():.1f}s of audio")
                event = await self._process_buffer(current_time_us)
                if event and self.transcription_callback:
                    await self.transcription_callback(event)
            await asyncio.sleep(0.1)  # Check every 100ms

    async def _process_buffer(self, flush_time_us: int) -> TranscriptionEvent | None:
        """Process the current buffer."""
        # Create transcription request using domain logic
        transcription_request = create_transcription_request(self.buffer_state)
        if not transcription_request:
            return None

        self.is_transcribing = True

        # Flush buffer using domain logic
        self.buffer_state = flush_buffer(self.buffer_state, flush_time_us)
        self.last_logged_duration = 0.0

        try:
            # Use transcription request data
            pcm_data = transcription_request.audio_data
            audio_format = transcription_request.format
            duration_seconds = (transcription_request.end_timestamp - transcription_request.start_timestamp) / 1_000_000

            logger.debug(
                f"Processing {duration_seconds:.1f}s of audio "
                f"({audio_format.sample_rate}Hz, {audio_format.channels}ch, {audio_format.bit_depth}bit)"
            )

            # Convert to float32 for Whisper
            audio_float = self._pcm_to_float32(pcm_data, audio_format)

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
                processing_start_time_ms = int(time.time() * 1000)
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

                processing_end_time_ms = int(time.time() * 1000)

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
                        processing_time = (processing_end_time_ms - processing_start_time_ms) / 1000
                        logger.info(f'Transcription ({processing_time:.2f}s): "{full_text}"')

                        # Format result using domain logic
                        transcription_result = format_transcription_result(
                            raw_text=full_text,
                            raw_confidence=None,  # whisper-cli doesn't provide confidence
                            request=transcription_request,
                            processing_start_time_ms=processing_start_time_ms,
                            processing_end_time_ms=processing_end_time_ms,
                        )

                        # Check if should emit using domain logic
                        if should_emit_transcription(transcription_result, self.min_confidence, self.min_words):
                            # Convert to legacy event format
                            return TranscriptionEvent(
                                timestamp=transcription_result.start_timestamp,
                                duration=duration_seconds,
                                text=transcription_result.text,
                            )
                        else:
                            logger.debug(
                                f"Transcription filtered: confidence={transcription_result.confidence}, words={transcription_result.word_count}"
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

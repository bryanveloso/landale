"""Correlates audio transcriptions with chat activity."""
import asyncio
import logging
from collections import deque, Counter
from datetime import datetime
from typing import List, Optional, Dict

from .events import TranscriptionEvent, ChatMessage, EmoteEvent, AnalysisResult
from .lms_client import LMSClient

logger = logging.getLogger(__name__)


class StreamCorrelator:
    """Correlates transcriptions with chat activity for contextual analysis."""
    
    def __init__(
        self,
        lms_client: LMSClient,
        context_window_seconds: int = 120,  # 2 minutes
        analysis_interval_seconds: int = 30,
        correlation_window_seconds: int = 10  # How far to look for chat reactions
    ):
        self.lms_client = lms_client
        self.context_window = context_window_seconds
        self.analysis_interval = analysis_interval_seconds
        self.correlation_window = correlation_window_seconds
        
        # Buffers for events
        self.transcription_buffer: deque[TranscriptionEvent] = deque()
        self.chat_buffer: deque[ChatMessage] = deque()
        self.emote_buffer: deque[EmoteEvent] = deque()
        
        # Analysis state
        self.last_analysis_time = 0
        self.is_analyzing = False
        
        # Trigger keywords that warrant immediate analysis
        self.trigger_keywords = [
            "let's go", "gg", "nice", "thank you", "game over",
            "what's that", "oh no", "yes", "finally", "got it"
        ]
        
        # Analysis result callbacks
        self._analysis_callbacks = []
        
    async def add_transcription(self, event: TranscriptionEvent):
        """Add a transcription event and potentially trigger analysis."""
        self.transcription_buffer.append(event)
        self._cleanup_old_events()
        
        # Check for trigger keywords
        if any(keyword in event.text.lower() for keyword in self.trigger_keywords):
            logger.info(f"Trigger keyword detected: {event.text}")
            await self.analyze(immediate=True)
            
    async def add_chat_message(self, event: ChatMessage):
        """Add a chat message event."""
        self.chat_buffer.append(event)
        self._cleanup_old_events()
        
    async def add_emote(self, event: EmoteEvent):
        """Add an emote usage event."""
        self.emote_buffer.append(event)
        self._cleanup_old_events()
        
    def on_analysis(self, callback):
        """Register a callback for analysis results."""
        self._analysis_callbacks.append(callback)
        
    async def analyze(self, immediate: bool = False) -> Optional[AnalysisResult]:
        """Perform correlation analysis."""
        # Skip if already analyzing
        if self.is_analyzing:
            return None
            
        # Apply cooldown unless immediate
        if not immediate:
            time_since_last = datetime.now().timestamp() - self.last_analysis_time
            if time_since_last < 10:  # 10 second cooldown
                return None
                
        self.is_analyzing = True
        self.last_analysis_time = datetime.now().timestamp()
        
        try:
            # Build transcription context
            transcription_context = self._build_transcription_context()
            if not transcription_context:
                return None
                
            # Build chat context with correlation
            chat_context = self._build_correlated_chat_context()
            
            # Calculate chat metrics
            chat_velocity = self._calculate_chat_velocity()
            emote_frequency = self._calculate_emote_frequency()
            
            # Send to LMS for analysis
            result = await self.lms_client.analyze(transcription_context, chat_context)
            
            if result:
                # Add correlation metrics
                result.chat_velocity = chat_velocity
                result.emote_frequency = emote_frequency
                
                logger.info(f"Analysis complete: {result.sentiment} sentiment, {len(result.topics)} topics")
                
                # Notify all callbacks
                for callback in self._analysis_callbacks:
                    await callback(result)
                
            return result
            
        except Exception as e:
            logger.error(f"Analysis failed: {e}")
            return None
            
        finally:
            self.is_analyzing = False
            
    async def periodic_analysis_loop(self):
        """Run periodic analysis."""
        while True:
            await asyncio.sleep(self.analysis_interval)
            await self.analyze()
            
    def _cleanup_old_events(self):
        """Remove events older than context window."""
        cutoff_time = datetime.now().timestamp() - self.context_window
        
        # Clean transcriptions
        while self.transcription_buffer and self.transcription_buffer[0].timestamp < cutoff_time:
            self.transcription_buffer.popleft()
            
        # Clean chat
        while self.chat_buffer and self.chat_buffer[0].timestamp < cutoff_time:
            self.chat_buffer.popleft()
            
        # Clean emotes
        while self.emote_buffer and self.emote_buffer[0].timestamp < cutoff_time:
            self.emote_buffer.popleft()
            
    def _build_transcription_context(self) -> str:
        """Build context string from recent transcriptions."""
        if not self.transcription_buffer:
            return ""
            
        # Join all recent transcriptions
        texts = [t.text for t in self.transcription_buffer]
        return " ".join(texts)
        
    def _build_correlated_chat_context(self) -> str:
        """Build chat context that correlates with recent speech."""
        if not self.chat_buffer or not self.transcription_buffer:
            return ""
            
        context_parts = []
        
        # For each transcription, find chat messages that came after it
        for transcription in self.transcription_buffer:
            # Find chat messages within correlation window
            correlated_messages = [
                msg for msg in self.chat_buffer
                if transcription.timestamp <= msg.timestamp <= transcription.timestamp + self.correlation_window
            ]
            
            if correlated_messages:
                chat_summary = self._summarize_chat_messages(correlated_messages)
                context_parts.append(f'After "{transcription.text}": {chat_summary}')
                
        return " | ".join(context_parts) if context_parts else self._summarize_all_recent_chat()
        
    def _summarize_chat_messages(self, messages: List[ChatMessage]) -> str:
        """Summarize a list of chat messages."""
        if not messages:
            return "no reaction"
            
        # Count emotes
        emote_counts = Counter()
        for msg in messages:
            for emote in msg.emotes:
                emote_counts[emote] += 1
                
        # Get sample messages
        sample_texts = [msg.message for msg in messages[:5] if msg.message]
        
        summary_parts = []
        
        if emote_counts:
            top_emotes = emote_counts.most_common(3)
            emote_str = ", ".join([f"{emote}x{count}" for emote, count in top_emotes])
            summary_parts.append(f"emotes: {emote_str}")
            
        if sample_texts:
            sample_str = " / ".join(sample_texts[:3])
            summary_parts.append(f"chat: {sample_str}")
            
        return f"{len(messages)} messages ({', '.join(summary_parts)})"
        
    def _summarize_all_recent_chat(self) -> str:
        """Summarize all recent chat when correlation isn't possible."""
        return self._summarize_chat_messages(list(self.chat_buffer))
        
    def _calculate_chat_velocity(self) -> float:
        """Calculate messages per minute."""
        if not self.chat_buffer:
            return 0.0
            
        # Get time span of messages
        oldest = self.chat_buffer[0].timestamp
        newest = self.chat_buffer[-1].timestamp
        time_span_minutes = (newest - oldest) / 60
        
        if time_span_minutes < 0.1:  # Less than 6 seconds
            return 0.0
            
        return len(self.chat_buffer) / time_span_minutes
        
    def _calculate_emote_frequency(self) -> Dict[str, int]:
        """Calculate emote usage frequency."""
        emote_counts = Counter()
        
        # Count from chat messages
        for msg in self.chat_buffer:
            for emote in msg.emotes:
                emote_counts[emote] += 1
                
        # Count from emote events
        for event in self.emote_buffer:
            emote_counts[event.emote_name] += 1
            
        return dict(emote_counts.most_common(10))  # Top 10 emotes
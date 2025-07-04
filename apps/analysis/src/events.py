"""Event models for stream analysis."""
from typing import List, Optional, Literal
from pydantic import BaseModel, Field


class TranscriptionEvent(BaseModel):
    """Audio transcription event from phononmaser."""
    timestamp: int
    text: str
    duration: float
    confidence: Optional[float] = None


class ChatMessage(BaseModel):
    """Chat message event from server."""
    timestamp: int
    username: str
    message: str
    emotes: List[str] = Field(default_factory=list)
    is_subscriber: bool = False
    is_moderator: bool = False
    
    
class EmoteEvent(BaseModel):
    """Emote usage event from server."""
    timestamp: int
    username: str
    emote_name: str
    emote_id: Optional[str] = None
    

class StreamPatterns(BaseModel):
    """Detected patterns in stream content."""
    technical_discussion: float = Field(ge=0, le=1)
    excitement: float = Field(ge=0, le=1)
    frustration: float = Field(ge=0, le=1)
    game_event: float = Field(ge=0, le=1)
    viewer_interaction: float = Field(ge=0, le=1)
    question: float = Field(ge=0, le=1)


class StreamDynamics(BaseModel):
    """How patterns are changing over time."""
    technical_discussion: Literal["increasing", "decreasing", "stable", "fluctuating"]
    excitement: Literal["increasing", "decreasing", "stable", "fluctuating"]
    frustration: Literal["increasing", "decreasing", "stable", "fluctuating"]
    game_event: Literal["increasing", "decreasing", "stable", "fluctuating"]
    viewer_interaction: Literal["increasing", "decreasing", "stable", "fluctuating"]
    overall_energy: Literal["building", "declining", "sustained", "volatile"]


class AnalysisResult(BaseModel):
    """Complete analysis of stream segment."""
    timestamp: int
    patterns: StreamPatterns
    dynamics: Optional[StreamDynamics] = None
    sentiment: Literal["positive", "negative", "neutral", "mixed"]
    sentiment_trajectory: Optional[Literal["improving", "declining", "stable", "swinging"]] = None
    topics: List[str] = Field(default_factory=list)
    context: str
    suggested_actions: List[str] = Field(default_factory=list)
    stream_momentum: Optional[dict] = None
    
    # Correlation data
    transcription_context: str
    chat_context: Optional[str] = None
    chat_velocity: Optional[float] = None  # messages per minute
    emote_frequency: Optional[dict] = None  # emote usage counts
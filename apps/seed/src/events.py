"""Event models for stream analysis."""
from typing import Any, Dict, List, Optional, Literal
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
    native_emotes: List[str] = Field(default_factory=list)  # avalon-prefixed emotes
    is_subscriber: bool = False
    is_moderator: bool = False
    
    
class EmoteEvent(BaseModel):
    """Emote usage event from server."""
    timestamp: int
    username: str
    emote_name: str
    emote_id: Optional[str] = None
    

class ViewerInteractionEvent(BaseModel):
    """Viewer interaction event (follows, subscriptions, cheers, etc.)."""
    timestamp: int
    interaction_type: Literal["follow", "subscription", "gift_subscription", "cheer"]
    username: str
    user_id: str
    details: dict = Field(default_factory=dict)  # Type-specific data like bits, tier, etc.
    

class FlexiblePatterns(BaseModel):
    """Flexible pattern detection without predetermined categories."""
    energy_level: float = Field(ge=0, le=1, description="Overall energy/intensity")
    engagement_depth: float = Field(ge=0, le=1, description="How deeply engaged the streamer is")
    community_sync: float = Field(ge=0, le=1, description="How in-sync chat is with streamer")
    content_focus: List[str] = Field(default_factory=list, description="Dynamic content themes")
    mood_indicators: Dict[str, float] = Field(default_factory=dict, description="Flexible mood tracking")
    temporal_flow: str = Field(description="How the context is evolving")


class StreamDynamics(BaseModel):
    """How stream elements are changing over time."""
    energy_trajectory: Literal["ramping_up", "winding_down", "steady_state", "volatile"]
    engagement_trend: Literal["deepening", "surfacing", "stable", "fluctuating"] 
    community_trend: Literal["synchronizing", "diverging", "stable", "chaotic"]
    content_evolution: Literal["focused", "exploring", "transitioning", "scattered"]
    overall_momentum: Literal["building", "declining", "sustained", "shifting"]


class RichContextData(BaseModel):
    """Rich context data for training and analysis."""
    # Temporal information
    timestamp: int
    duration: float
    session_id: str
    
    # Content data
    transcript: str
    transcript_fragments: List[dict] = Field(default_factory=list)  # Raw Whisper outputs
    confidence_scores: List[float] = Field(default_factory=list)
    speaking_patterns: Dict[str, Any] = Field(default_factory=dict)  # Pace, pauses, etc.
    
    # Community data
    chat_messages: List[dict] = Field(default_factory=list)
    emote_usage: Dict[str, Any] = Field(default_factory=dict)
    viewer_interactions: List[dict] = Field(default_factory=list)
    community_metrics: Dict[str, Any] = Field(default_factory=dict)
    
    # Correlation analysis
    correlation_data: Dict[str, Any] = Field(default_factory=dict)
    temporal_patterns: Dict[str, Any] = Field(default_factory=dict)
    
    # AI analysis (flexible structure)
    ai_analysis: Optional[Dict[str, Any]] = None
    model_metadata: Dict[str, str] = Field(default_factory=dict)  # model, version, etc.


class AnalysisResult(BaseModel):
    """Complete analysis of stream segment."""
    timestamp: int
    patterns: FlexiblePatterns
    dynamics: Optional[StreamDynamics] = None
    sentiment: Literal["positive", "negative", "neutral", "mixed"]
    sentiment_trajectory: Optional[Literal["improving", "declining", "stable", "swinging"]] = None
    topics: List[str] = Field(default_factory=list)
    context: str
    suggested_actions: List[str] = Field(default_factory=list)
    stream_momentum: Optional[dict] = None
    
    # Rich context data
    rich_context: Optional[RichContextData] = None
    
    # Legacy correlation data (for backward compatibility)
    transcription_context: str
    chat_context: Optional[str] = None
    chat_velocity: Optional[float] = None  # messages per minute
    emote_frequency: Optional[dict] = None  # emote usage counts
    native_emote_frequency: Optional[dict] = None  # avalon-prefixed emote counts
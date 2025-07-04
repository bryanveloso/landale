"""LM Studio client for AI analysis."""
import json
import logging
from typing import Optional
import aiohttp

from .events import FlexiblePatterns, StreamDynamics, AnalysisResult, RichContextData

logger = logging.getLogger(__name__)


class LMSClient:
    """Client for LM Studio API."""
    
    def __init__(self, api_url: str = "http://zelan:1234/v1", model: str = "dolphin-2.9.3-llama-3-8b"):
        self.api_url = api_url
        self.model = model
        self.session: Optional[aiohttp.ClientSession] = None
        
    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession()
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()
            
    async def analyze(self, transcription_context: str, chat_context: Optional[str] = None) -> Optional[AnalysisResult]:
        """Analyze stream context and return insights."""
        if not self.session:
            raise RuntimeError("LMSClient must be used as async context manager")
            
        prompt = self._build_prompt(transcription_context, chat_context)
        
        try:
            async with self.session.post(
                f"{self.api_url}/chat/completions",
                json={
                    "model": self.model,
                    "messages": [
                        {
                            "role": "system",
                            "content": "You are analyzing a live stream. Provide insights on patterns, dynamics, and sentiment. Always respond with valid JSON."
                        },
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "temperature": 0.7,
                    "max_tokens": 800
                }
            ) as response:
                if response.status != 200:
                    logger.error(f"LMS API error: {response.status}")
                    return None
                    
                data = await response.json()
                content = data["choices"][0]["message"]["content"]
                
                # Parse JSON response
                result_data = json.loads(content)
                
                # Convert to AnalysisResult
                return AnalysisResult(
                    timestamp=int(result_data.get("timestamp", 0)),
                    patterns=FlexiblePatterns(**result_data["patterns"]),
                    dynamics=StreamDynamics(**result_data["dynamics"]) if "dynamics" in result_data else None,
                    sentiment=result_data["sentiment"],
                    sentiment_trajectory=result_data.get("sentimentTrajectory"),
                    topics=result_data.get("topics", []),
                    context=result_data["context"],
                    suggested_actions=result_data.get("suggestedActions", []),
                    stream_momentum=result_data.get("streamMomentum"),
                    transcription_context=transcription_context,
                    chat_context=chat_context
                )
                
        except Exception as e:
            logger.error(f"Failed to analyze with LMS: {e}")
            return None
            
    def _build_prompt(self, transcription_context: str, chat_context: Optional[str] = None) -> str:
        """Build analysis prompt with available context."""
        base_prompt = f"""You are analyzing a streamer's content to build training data. This represents the last 2 minutes.

Streamer's speech: "{transcription_context}"
"""
        
        if chat_context:
            base_prompt += f"""
Chat reactions: "{chat_context}"

Analyze BOTH the streamer's words AND how chat is reacting. Consider:
- Is chat responding to what the streamer said?
- What emotions or reactions is chat showing?
- Are there any disconnects between streamer mood and chat mood?
"""
        
        base_prompt += """
Provide flexible analysis for training data collection:
1. Energy level and engagement depth
2. How content and community are evolving
3. Dynamic topics and mood indicators
4. Overall momentum and flow

Respond with JSON in this exact format:
{
  "timestamp": <current_unix_timestamp>,
  "patterns": {
    "energy_level": 0.0-1.0,
    "engagement_depth": 0.0-1.0,
    "community_sync": 0.0-1.0,
    "content_focus": ["topic1", "topic2"],
    "mood_indicators": {"mood_name": 0.0-1.0},
    "temporal_flow": "description of how things are evolving"
  },
  "dynamics": {
    "energy_trajectory": "ramping_up|winding_down|steady_state|volatile",
    "engagement_trend": "deepening|surfacing|stable|fluctuating",
    "community_trend": "synchronizing|diverging|stable|chaotic",
    "content_evolution": "focused|exploring|transitioning|scattered",
    "overall_momentum": "building|declining|sustained|shifting"
  },
  "sentiment": "positive|negative|neutral|mixed",
  "sentimentTrajectory": "improving|declining|stable|swinging",
  "topics": ["emergent_topic1", "emergent_topic2"],
  "context": "rich description of what's happening and why",
  "suggestedActions": ["action1", "action2"],
  "streamMomentum": {
    "description": "what's driving the current flow",
    "direction": "ramping_up|winding_down|steady_state|chaotic"
  }
}"""
        
        return base_prompt
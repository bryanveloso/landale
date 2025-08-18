"""Simple LM Studio client for RAG queries using the official Python SDK."""

import asyncio

import lmstudio as lms
from lmstudio import BaseModel

from .logger import get_logger

logger = get_logger(__name__)


class RAGResponse(BaseModel):
    """Structured response schema for RAG queries."""

    answer: str  # Main response to the user's question
    confidence: float  # 0.0-1.0 confidence in the answer
    reasoning: str  # Brief explanation of how the answer was derived
    response_type: str  # "factual", "creative", "clarification", "insufficient_data"
    suggestions: list[str] | None = None  # Follow-up suggestions (for creative responses)


class RAGLMSClient:
    """Simplified LMS client specifically for RAG queries using LM Studio Python SDK."""

    def __init__(
        self,
        base_url: str = "http://zelan:1234",
        model: str = "deepseek/deepseek-r1-0528-qwen3-8b",
        temperature: float = 0.8,
        max_tokens: int = 500,
        top_p: float = 0.9,
    ):
        self.base_url = base_url
        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.top_p = top_p
        self.llm_model = None
        logger.info(f"RAG LMS Client config: temp={temperature}, max_tokens={max_tokens}, top_p={top_p}")

    async def __aenter__(self):
        """Async context manager entry."""
        try:
            # Use the convenience API to get a model
            self.llm_model = await asyncio.to_thread(lms.llm, self.model)
            logger.info(f"RAG LMS client initialized with model {self.model}")
            return self
        except Exception as e:
            logger.error(f"Failed to initialize RAG LMS client: {e}")
            self.llm_model = None
            return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.llm_model:
            # LM Studio convenience API handles cleanup automatically
            self.llm_model = None

    async def generate_response(self, prompt: str) -> dict | None:
        """Generate a structured response for RAG queries."""
        if not self.llm_model:
            logger.error("RAG LMS client not initialized")
            return None

        try:
            logger.info(f"RAG LMS: Starting structured generation request to {self.base_url} with model {self.model}")
            logger.info(f"RAG LMS: Prompt length: {len(prompt)} chars")
            logger.debug(f"RAG LMS: Prompt preview: {prompt[:200]}...")

            # Use the convenience API with configurable parameters and structured response
            config = {"temperature": self.temperature, "maxTokens": self.max_tokens, "topP": self.top_p}

            logger.debug(f"RAG LMS: Using config: {config}")
            response = await asyncio.to_thread(self.llm_model.respond, prompt, config, schema=RAGResponse)

            logger.info(f"RAG LMS: Received response object: {type(response)}")

            if response and hasattr(response, "parsed"):
                # Get the structured data from the parsed field
                structured_data = response.parsed
                logger.info(f"RAG LMS structured response generated: {structured_data.response_type}")
                logger.debug(f"RAG LMS response preview: {structured_data.answer[:100]}...")

                # Convert to dict for easier handling
                return {
                    "answer": structured_data.answer,
                    "confidence": structured_data.confidence,
                    "reasoning": structured_data.reasoning,
                    "response_type": structured_data.response_type,
                    "suggestions": structured_data.suggestions,
                }
            else:
                logger.warning(f"RAG LMS: No parsed field in response: {response}")
                # Fallback to content if structured parsing fails
                if hasattr(response, "content"):
                    content = response.content.strip()
                    return {
                        "answer": content,
                        "confidence": 0.5,
                        "reasoning": "Unstructured fallback response",
                        "response_type": "fallback",
                        "suggestions": None,
                    }
                return None

        except Exception as e:
            logger.error(f"RAG LMS generation failed: {e}", exc_info=True)
            return None

    def is_available(self) -> bool:
        """Check if the LMS client is available."""
        return self.llm_model is not None

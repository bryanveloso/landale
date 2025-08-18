"""Simple LM Studio client for RAG queries using the official Python SDK."""

import asyncio

import lmstudio as lms

from .logger import get_logger

logger = get_logger(__name__)


class RAGLMSClient:
    """Simplified LMS client specifically for RAG queries using LM Studio Python SDK."""

    def __init__(self, base_url: str = "http://zelan:1234", model: str = "deepseek/deepseek-r1-0528-qwen3-8b"):
        self.base_url = base_url
        self.model = model
        self.llm_model = None

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

    async def generate_response(self, prompt: str) -> str | None:
        """Generate a simple text response for RAG queries."""
        if not self.llm_model:
            logger.error("RAG LMS client not initialized")
            return None

        try:
            logger.info(f"RAG LMS: Starting generation request to {self.base_url} with model {self.model}")
            logger.info(f"RAG LMS: Prompt length: {len(prompt)} chars")
            logger.debug(f"RAG LMS: Prompt preview: {prompt[:200]}...")

            # Use the convenience API for simple text completion
            response = await asyncio.to_thread(self.llm_model.respond, prompt)

            logger.info(f"RAG LMS: Received response object: {type(response)}")
            logger.debug(f"RAG LMS: Response attributes: {dir(response) if response else 'None'}")

            if response and hasattr(response, "content"):
                content = response.content.strip()
                logger.info(f"RAG LMS response generated ({len(content)} chars)")
                logger.debug(f"RAG LMS: Response content preview: {content[:200]}...")
                return content
            else:
                logger.warning(f"Empty response from LMS - response: {response}")
                return None

        except Exception as e:
            logger.error(f"RAG LMS generation failed: {e}", exc_info=True)
            return None

    def is_available(self) -> bool:
        """Check if the LMS client is available."""
        return self.llm_model is not None

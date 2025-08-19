"""Mock implementations and fixtures for PromptManager testing."""

import asyncio
import json
import time
from typing import Any
from unittest.mock import Mock

import aiohttp


class MockHttpResponse:
    """Mock HTTP response for testing."""

    def __init__(self, status: int = 200, json_data: Any = None, text_data: str = ""):
        self.status = status
        self._json_data = json_data
        self._text_data = text_data
        self.request_info = Mock()
        self.history = []

    async def json(self):
        if self._json_data is None:
            raise json.JSONDecodeError("No JSON data", "", 0)
        return self._json_data

    async def text(self):
        return self._text_data

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass


class MockHttpSession:
    """Mock HTTP session for testing."""

    def __init__(self):
        self.responses = []
        self.requests = []
        self.timeout = aiohttp.ClientTimeout(total=10.0, connect=5.0)
        self.closed = False

    def add_response(self, response: MockHttpResponse):
        """Add a response to the queue."""
        self.responses.append(response)

    def get(self, url: str, params: dict = None):
        """Mock GET request."""
        self.requests.append({"method": "GET", "url": url, "params": params})

        if self.responses:
            return self.responses.pop(0)
        else:
            # Default successful response
            return MockHttpResponse(200, {"events": []})

    async def close(self):
        """Mock session close."""
        self.closed = True


class MockCircuitBreaker:
    """Mock circuit breaker for testing."""

    def __init__(self, name: str = "test", **kwargs):  # noqa: ARG002
        self.name = name
        self.state = "closed"
        self.failure_count = 0
        self.success_count = 0
        self.total_calls = 0
        self.total_failures = 0
        self.total_successes = 0
        self.total_rejections = 0
        self.last_failure_time = 0.0
        self.last_state_change = time.time()
        self.call_history = []
        self.should_fail = False
        self.failure_exception = Exception("Circuit breaker test failure")

    def set_failure_mode(self, should_fail: bool, exception: Exception = None):
        """Control whether the circuit breaker should fail."""
        self.should_fail = should_fail
        if exception:
            self.failure_exception = exception

    async def call(self, func, *args, **kwargs):
        """Mock circuit breaker call."""
        self.total_calls += 1
        self.call_history.append({"func": func, "args": args, "kwargs": kwargs})

        if self.should_fail:
            self.total_failures += 1
            self.failure_count += 1
            self.last_failure_time = time.time()
            if self.failure_count >= 3:  # Mock threshold
                self.state = "open"
            raise self.failure_exception
        else:
            self.total_successes += 1
            self.failure_count = 0
            if self.state == "open":
                self.state = "half_open"
            elif self.state == "half_open":
                self.success_count += 1
                if self.success_count >= 2:  # Mock recovery threshold
                    self.state = "closed"
                    self.success_count = 0
            return await func(*args, **kwargs)

    def get_stats(self) -> dict[str, Any]:
        """Get circuit breaker statistics."""
        return {
            "name": self.name,
            "state": self.state,
            "failure_count": self.failure_count,
            "success_count": self.success_count,
            "total_calls": self.total_calls,
            "total_failures": self.total_failures,
            "total_successes": self.total_successes,
            "total_rejections": self.total_rejections,
            "last_failure_time": self.last_failure_time,
            "time_in_current_state": time.time() - self.last_state_change,
            "success_rate": (self.total_successes / self.total_calls if self.total_calls > 0 else 0.0),
        }


class MockPromptManager:
    """Mock PromptManager for testing AudioProcessor integration."""

    def __init__(self, **kwargs):
        self.running = False
        self.current_prompt = ""
        self.last_prompt_update = 0.0
        self.prompt_expiry_minutes = kwargs.get("prompt_expiry_minutes", 5)
        self.stats = {
            "total_polls": 0,
            "successful_polls": 0,
            "failed_polls": 0,
            "prompts_generated": 0,
            "circuit_breaker_opens": 0,
            "last_success_time": 0.0,
            "last_error": None,
        }
        self.should_fail = False
        self.failure_exception = Exception("Mock PromptManager failure")

    async def start(self):
        """Mock start method."""
        self.running = True

    async def stop(self):
        """Mock stop method."""
        self.running = False

    def get_current_prompt(self) -> str:
        """Mock get_current_prompt method."""
        if self.should_fail:
            raise self.failure_exception

        # Check expiry
        if time.time() - self.last_prompt_update > (self.prompt_expiry_minutes * 60) and self.current_prompt:
            self.current_prompt = ""

        return self.current_prompt

    def set_prompt(self, prompt: str):
        """Set the current prompt for testing."""
        self.current_prompt = prompt
        self.last_prompt_update = time.time()

    def set_failure_mode(self, should_fail: bool, exception: Exception = None):
        """Control whether get_current_prompt should fail."""
        self.should_fail = should_fail
        if exception:
            self.failure_exception = exception

    def get_stats(self) -> dict[str, Any]:
        """Mock get_stats method."""
        return {
            **self.stats,
            "current_prompt_length": len(self.current_prompt),
            "prompt_age_seconds": time.time() - self.last_prompt_update if self.last_prompt_update > 0 else 0,
            "time_since_last_poll": 0,
            "circuit_breaker": {
                "name": "mock_circuit",
                "state": "closed",
                "failure_count": 0,
                "total_calls": 0,
            },
            "running": self.running,
        }


class ChatEventGenerator:
    """Generate realistic chat events for testing."""

    def __init__(self):
        self.usernames = [
            "alice",
            "bob",
            "charlie",
            "diana",
            "eve",
            "frank",
            "grace",
            "henry",
            "iris",
            "jack",
            "kelly",
            "liam",
        ]
        self.message_count = 0

    def generate_events(self, count: int, time_range_minutes: int = 10) -> list[dict]:
        """Generate chat events for testing."""
        events = []
        base_time = time.time() - (time_range_minutes * 60)

        for i in range(count):
            username = self.usernames[i % len(self.usernames)]
            timestamp = base_time + (i * (time_range_minutes * 60) / count)

            event = {
                "id": f"event_{self.message_count + i}",
                "timestamp": timestamp,
                "event_type": "channel.chat.message",
                "event_data": {
                    "username": username,
                    "message": f"Test message {i} from {username}",
                    "channel": "general",
                },
            }
            events.append(event)

        self.message_count += count
        return events

    def generate_events_with_frequency(self, username_frequencies: dict[str, int]) -> list[dict]:
        """Generate events with specific username frequencies."""
        events = []
        event_id = 0

        for username, frequency in username_frequencies.items():
            for i in range(frequency):
                event = {
                    "id": f"event_{event_id}",
                    "timestamp": time.time() - (60 * i),  # Spread over last hour
                    "event_type": "channel.chat.message",
                    "event_data": {
                        "username": username,
                        "message": f"Message {i} from {username}",
                        "channel": "general",
                    },
                }
                events.append(event)
                event_id += 1

        return events

    def generate_malformed_events(self) -> list[dict]:
        """Generate malformed events for error testing."""
        return [
            # Missing event_data
            {"id": "bad1", "timestamp": time.time()},
            # Invalid username types
            {"event_data": {"username": None}},
            {"event_data": {"username": 123}},
            {"event_data": {"username": ""}},
            {"event_data": {"username": "   "}},
            # Username too long
            {"event_data": {"username": "x" * 100}},
            # Different field names
            {"data": {"user_name": "valid_user"}},
            {"event_data": {"author": "another_user"}},
            # Completely invalid structure
            "not_a_dict",
            {"random": "fields"},
        ]


class PromptManagerTestSuite:
    """Comprehensive test suite utilities for PromptManager."""

    @staticmethod
    def create_api_response(events: list[dict]) -> dict:
        """Create a realistic API response."""
        return {
            "events": events,
            "total": len(events),
            "has_more": False,
            "next_cursor": None,
        }

    @staticmethod
    def create_error_response(status: int, message: str) -> MockHttpResponse:
        """Create an error response."""
        return MockHttpResponse(status=status, text_data=message)

    @staticmethod
    def create_json_error_response() -> MockHttpResponse:
        """Create a response that will cause JSON decode error."""
        return MockHttpResponse(status=200, text_data="Invalid JSON {")

    @staticmethod
    async def simulate_network_delay(delay_seconds: float = 0.1):
        """Simulate network delay in tests."""
        await asyncio.sleep(delay_seconds)

    @staticmethod
    def verify_api_call_params(session: MockHttpSession, expected_params: dict):
        """Verify that API was called with expected parameters."""
        assert len(session.requests) > 0
        last_request = session.requests[-1]
        assert last_request["method"] == "GET"

        if expected_params:
            actual_params = last_request["params"] or {}
            for key, value in expected_params.items():
                assert key in actual_params
                if key != "since":  # since is a timestamp, so we check format
                    assert actual_params[key] == value
                else:
                    # Verify timestamp format
                    assert "T" in actual_params[key]
                    assert actual_params[key].endswith("Z")

    @staticmethod
    def create_stress_test_events(user_count: int = 100, messages_per_user: int = 10) -> list[dict]:
        """Create a large number of events for stress testing."""
        generator = ChatEventGenerator()
        events = []

        for user_id in range(user_count):
            username = f"stress_user_{user_id:03d}"
            user_events = generator.generate_events_with_frequency({username: messages_per_user})
            events.extend(user_events)

        return events

    @staticmethod
    def assert_prompt_format(prompt: str, max_chars: int = 200):
        """Assert that a generated prompt follows the expected format."""
        if prompt:
            assert prompt.startswith("Participants include:")
            assert prompt.endswith(".")
            assert len(prompt) <= max_chars

            # Extract usernames
            content = prompt[len("Participants include: ") : -1]
            if content:
                usernames = [name.strip() for name in content.split(",")]
                # All usernames should be non-empty
                assert all(username for username in usernames)

    @staticmethod
    def measure_performance(func):
        """Decorator to measure function performance."""

        async def wrapper(*args, **kwargs):
            start_time = time.time()
            result = await func(*args, **kwargs)
            end_time = time.time()
            execution_time = end_time - start_time
            return result, execution_time

        return wrapper


# Test fixtures using the mock classes
def create_mock_prompt_manager(**kwargs):
    """Create a mock PromptManager with default configuration."""
    return MockPromptManager(**kwargs)


def create_mock_http_session():
    """Create a mock HTTP session."""
    return MockHttpSession()


def create_mock_circuit_breaker(**kwargs):
    """Create a mock circuit breaker."""
    return MockCircuitBreaker(**kwargs)


def create_chat_event_generator():
    """Create a chat event generator."""
    return ChatEventGenerator()


# Common test data
SAMPLE_CHAT_EVENTS = [
    {
        "id": "event_1",
        "timestamp": time.time() - 300,  # 5 minutes ago
        "event_type": "channel.chat.message",
        "event_data": {
            "username": "alice",
            "message": "Hello everyone!",
            "channel": "general",
        },
    },
    {
        "id": "event_2",
        "timestamp": time.time() - 240,  # 4 minutes ago
        "event_type": "channel.chat.message",
        "event_data": {
            "username": "bob",
            "message": "How's everyone doing?",
            "channel": "general",
        },
    },
    {
        "id": "event_3",
        "timestamp": time.time() - 180,  # 3 minutes ago
        "event_type": "channel.chat.message",
        "event_data": {
            "username": "alice",
            "message": "Great stream today!",
            "channel": "general",
        },
    },
]

MALFORMED_CHAT_EVENTS = [
    {"invalid": "structure"},
    {"event_data": {"username": None}},
    {"event_data": {"username": ""}},
    {"event_data": {"username": 123}},
    {"data": {"user_name": "valid_user"}},
]

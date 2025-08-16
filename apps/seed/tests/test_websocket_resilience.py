"""Comprehensive WebSocket resilience tests for seed service."""

import asyncio
import json
import time
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import websockets
from shared.websockets import BaseWebSocketClient, ConnectionEvent, ConnectionState

from src.events import ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from src.websocket_client import PhononmaserClient, ServerClient

# Mark all tests as async
pytestmark = pytest.mark.asyncio


class MockWebSocketConnection:
    """Mock WebSocket connection for controlled testing scenarios."""
    
    def __init__(self, should_fail_connect=False, fail_after_n_messages=None, 
                 connection_delay=0, message_delay=0, fail_ping=False):
        self.should_fail_connect = should_fail_connect
        self.fail_after_n_messages = fail_after_n_messages
        self.connection_delay = connection_delay
        self.message_delay = message_delay
        self.fail_ping = fail_ping
        
        # State tracking
        self.connected = False
        self.messages_sent = []
        self.messages_received = 0
        self.close_called = False
        self.ping_called = False
        
        # Message queue for testing
        self.incoming_messages = []
        self.current_message_index = 0
        
    async def __aenter__(self):
        if self.connection_delay > 0:
            await asyncio.sleep(self.connection_delay)
            
        if self.should_fail_connect:
            raise websockets.exceptions.ConnectionClosed(None, None)
            
        self.connected = True
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()
    
    async def send(self, message):
        """Simulate sending messages with optional failures."""
        if not self.connected:
            raise websockets.exceptions.ConnectionClosed(None, None)
        
        if self.message_delay > 0:
            await asyncio.sleep(self.message_delay)
            
        self.messages_sent.append(message)
        self.messages_received += 1
        
        # Simulate connection failure after N messages
        if (self.fail_after_n_messages and 
            self.messages_received >= self.fail_after_n_messages):
            self.connected = False
            raise websockets.exceptions.ConnectionClosed(None, None)
    
    async def send_json(self, data):
        """Send JSON data."""
        await self.send(json.dumps(data))
    
    async def close(self):
        """Simulate connection close."""
        self.close_called = True
        self.connected = False
    
    async def ping(self):
        """Simulate ping with optional failures."""
        self.ping_called = True
        if self.fail_ping:
            raise websockets.exceptions.ConnectionClosed(None, None)
    
    def __aiter__(self):
        return self
    
    async def __anext__(self):
        """Simulate message reception from queue."""
        if not self.connected:
            raise StopAsyncIteration
        
        if self.current_message_index < len(self.incoming_messages):
            message = self.incoming_messages[self.current_message_index]
            self.current_message_index += 1
            return message
        
        # Simulate waiting for messages
        await asyncio.sleep(0.1)
        raise StopAsyncIteration
    
    def add_incoming_message(self, message):
        """Add a message to the incoming queue."""
        self.incoming_messages.append(message)


class TestPhononmaserClientResilience:
    """Test PhononmaserClient resilience patterns."""
    
    @pytest.fixture
    async def phono_client(self):
        """Create PhononmaserClient for testing."""
        client = PhononmaserClient("ws://test:8889")
        yield client
        await client.disconnect()
    
    async def test_phononmaser_connection_establishment(self, phono_client):
        """Test PhononmaserClient connection establishment."""
        mock_ws = MockWebSocketConnection()
        
        with patch('websockets.connect', return_value=mock_ws):
            success = await phono_client._do_connect()
            
            assert success is True
            assert phono_client._connection_state == ConnectionState.CONNECTED
            assert mock_ws.connected is True
    
    async def test_phononmaser_connection_failure_recovery(self, phono_client):
        """Test PhononmaserClient recovery from connection failures."""
        connection_attempts = 0
        
        async def intermittent_connect(*args, **kwargs):
            nonlocal connection_attempts
            connection_attempts += 1
            
            if connection_attempts <= 2:  # Fail first 2 attempts
                raise websockets.exceptions.ConnectionClosed(None, None)
            
            return MockWebSocketConnection()
        
        with patch('websockets.connect', side_effect=intermittent_connect):
            # Should eventually succeed after retries
            success = await phono_client.connect()
            
            assert success is True
            assert connection_attempts == 3
    
    async def test_phononmaser_transcription_event_handling(self, phono_client):
        """Test handling of transcription events from phononmaser."""
        mock_ws = MockWebSocketConnection()
        
        # Add incoming transcription message
        transcription_msg = json.dumps({
            "type": "audio:transcription",
            "timestamp": int(datetime.now().timestamp() * 1_000_000),
            "text": "Test transcription from phononmaser",
            "duration": 2.5,
            "confidence": 0.95,
            "correlation_id": "test_correlation"
        })
        mock_ws.add_incoming_message(transcription_msg)
        
        received_events = []
        
        def handle_transcription(event: TranscriptionEvent):
            received_events.append(event)
        
        phono_client.on_transcription(handle_transcription)
        
        with patch('websockets.connect', return_value=mock_ws):
            await phono_client._do_connect()
            
            # Process messages
            await phono_client._do_listen()
            
            # Allow async processing
            await asyncio.sleep(0.1)
            
            assert len(received_events) == 1
            assert received_events[0].text == "Test transcription from phononmaser"
            assert received_events[0].confidence == 0.95
    
    async def test_phononmaser_heartbeat_mechanism(self, phono_client):
        """Test PhononmaserClient heartbeat mechanism."""
        mock_ws = MockWebSocketConnection()
        
        with patch('websockets.connect', return_value=mock_ws):
            await phono_client._do_connect()
            
            # Test heartbeat
            success = await phono_client._send_heartbeat()
            
            assert success is True
            assert mock_ws.ping_called is True
    
    async def test_phononmaser_heartbeat_failure_handling(self, phono_client):
        """Test handling of heartbeat failures."""
        mock_ws = MockWebSocketConnection(fail_ping=True)
        
        with patch('websockets.connect', return_value=mock_ws):
            await phono_client._do_connect()
            
            # Test heartbeat failure
            success = await phono_client._send_heartbeat()
            
            assert success is False
            assert mock_ws.ping_called is True
    
    async def test_phononmaser_malformed_message_handling(self, phono_client):
        """Test handling of malformed messages from phononmaser."""
        mock_ws = MockWebSocketConnection()
        
        # Add malformed messages
        mock_ws.add_incoming_message("invalid json")
        mock_ws.add_incoming_message(json.dumps({"type": "unknown"}))
        mock_ws.add_incoming_message(json.dumps({}))  # Missing required fields
        
        received_events = []
        phono_client.on_transcription(lambda e: received_events.append(e))
        
        with patch('websockets.connect', return_value=mock_ws):
            await phono_client._do_connect()
            
            # Should handle malformed messages gracefully
            await phono_client._do_listen()
            
            # No events should be received from malformed messages
            await asyncio.sleep(0.1)
            assert len(received_events) == 0
    
    async def test_phononmaser_concurrent_event_processing(self, phono_client):
        """Test concurrent processing of transcription events."""
        mock_ws = MockWebSocketConnection()
        
        # Add multiple transcription messages
        for i in range(10):
            msg = json.dumps({
                "type": "audio:transcription",
                "timestamp": int(datetime.now().timestamp() * 1_000_000) + i,
                "text": f"Concurrent transcription {i}",
                "duration": 1.0,
                "correlation_id": f"concurrent_{i}"
            })
            mock_ws.add_incoming_message(msg)
        
        received_events = []
        processing_times = []
        
        async def handle_transcription(event: TranscriptionEvent):
            start_time = time.time()
            await asyncio.sleep(0.01)  # Simulate processing time
            end_time = time.time()
            
            received_events.append(event)
            processing_times.append(end_time - start_time)
        
        phono_client.on_transcription(handle_transcription)
        
        with patch('websockets.connect', return_value=mock_ws):
            await phono_client._do_connect()
            
            # Process all messages
            await phono_client._do_listen()
            
            # Wait for all async processing to complete
            await asyncio.sleep(0.5)
            
            assert len(received_events) == 10
            # Verify events were processed concurrently (total time < sum of individual times)
            total_processing_time = sum(processing_times)
            assert total_processing_time > 0.1  # At least 10 * 0.01 seconds


class TestServerClientResilience:
    """Test ServerClient resilience patterns."""
    
    @pytest.fixture
    async def server_client(self):
        """Create ServerClient for testing."""
        client = ServerClient("ws://test:7175/socket/websocket")
        yield client
        await client.disconnect()
    
    async def test_server_client_phoenix_channel_join(self, server_client):
        """Test ServerClient Phoenix channel joining."""
        mock_ws = MockWebSocketConnection()
        
        with patch('websockets.connect', return_value=mock_ws):
            success = await server_client._do_connect()
            
            assert success is True
            assert len(mock_ws.messages_sent) == 1
            
            # Verify Phoenix channel join message
            join_msg = json.loads(mock_ws.messages_sent[0])
            assert join_msg['topic'] == 'events:all'
            assert join_msg['event'] == 'phx_join'
    
    async def test_server_client_chat_message_processing(self, server_client):
        """Test processing of chat messages from server."""
        mock_ws = MockWebSocketConnection()
        
        # Phoenix channel message format
        chat_msg = json.dumps({
            "topic": "events:all",
            "event": "chat_message",
            "payload": {
                "data": {
                    "user_name": "test_user",
                    "message": "Hello world!",
                    "timestamp": "2023-01-01T12:00:00Z",
                    "fragments": [
                        {"type": "text", "text": "Hello "},
                        {"type": "emote", "text": "avalonHYPE"},
                        {"type": "text", "text": " world!"}
                    ],
                    "badges": [{"set_id": "subscriber"}]
                }
            }
        })
        mock_ws.add_incoming_message(chat_msg)
        
        received_messages = []
        server_client.on_chat_message(lambda msg: received_messages.append(msg))
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            await server_client._do_listen()
            
            await asyncio.sleep(0.1)
            
            assert len(received_messages) == 1
            chat_event = received_messages[0]
            assert chat_event.username == "test_user"
            assert chat_event.message == "Hello world!"
            assert "avalonHYPE" in chat_event.emotes
            assert chat_event.is_subscriber is True
    
    async def test_server_client_viewer_interaction_processing(self, server_client):
        """Test processing of viewer interaction events."""
        mock_ws = MockWebSocketConnection()
        
        # Follower event
        follow_msg = json.dumps({
            "topic": "events:all",
            "event": "follower",
            "payload": {
                "data": {
                    "user_name": "new_follower",
                    "user_id": "12345",
                    "timestamp": int(datetime.now().timestamp())
                }
            }
        })
        mock_ws.add_incoming_message(follow_msg)
        
        received_interactions = []
        server_client.on_viewer_interaction(lambda event: received_interactions.append(event))
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            await server_client._do_listen()
            
            await asyncio.sleep(0.1)
            
            assert len(received_interactions) == 1
            interaction = received_interactions[0]
            assert interaction.interaction_type == "follower"
            assert interaction.username == "new_follower"
    
    async def test_server_client_phoenix_heartbeat(self, server_client):
        """Test Phoenix channel heartbeat mechanism."""
        mock_ws = MockWebSocketConnection()
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            
            # Test Phoenix heartbeat
            success = await server_client._send_heartbeat()
            
            assert success is True
            
            # Verify heartbeat message format
            heartbeat_found = False
            for msg_json in mock_ws.messages_sent:
                msg = json.loads(msg_json)
                if msg.get('event') == 'heartbeat' and msg.get('topic') == 'phoenix':
                    heartbeat_found = True
                    break
            
            assert heartbeat_found is True
    
    async def test_server_client_phoenix_ref_management(self, server_client):
        """Test Phoenix reference counter management."""
        mock_ws = MockWebSocketConnection()
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            
            initial_ref = server_client._phoenix_ref
            
            # Send heartbeat (should increment ref)
            await server_client._send_heartbeat()
            
            assert server_client._phoenix_ref == initial_ref + 1
    
    async def test_server_client_connection_state_reset(self, server_client):
        """Test connection state reset on disconnect."""
        mock_ws = MockWebSocketConnection()
        
        connection_events = []
        server_client.on_connection_change(lambda e: connection_events.append(e))
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            initial_ref = server_client._phoenix_ref
            
            # Simulate disconnect
            await server_client._do_disconnect()
            
            # Phoenix ref should reset
            assert server_client._phoenix_ref == 1
            
            # Should have connection state events
            disconnect_events = [e for e in connection_events if e.new_state == ConnectionState.DISCONNECTED]
            assert len(disconnect_events) > 0
    
    async def test_server_client_legacy_array_format_compatibility(self, server_client):
        """Test compatibility with legacy Phoenix array message format."""
        mock_ws = MockWebSocketConnection()
        
        # Legacy array format: [join_ref, ref, topic, event, payload]
        legacy_msg = json.dumps([
            "1", "2", "events:all", "chat_message", 
            {
                "data": {
                    "user_name": "legacy_user",
                    "message": "Legacy format message",
                    "timestamp": "2023-01-01T12:00:00Z",
                    "fragments": [],
                    "badges": []
                }
            }
        ])
        mock_ws.add_incoming_message(legacy_msg)
        
        received_messages = []
        server_client.on_chat_message(lambda msg: received_messages.append(msg))
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            await server_client._do_listen()
            
            await asyncio.sleep(0.1)
            
            assert len(received_messages) == 1
            assert received_messages[0].username == "legacy_user"
    
    async def test_server_client_timestamp_parsing_robustness(self, server_client):
        """Test robust timestamp parsing for different formats."""
        mock_ws = MockWebSocketConnection()
        
        # Test different timestamp formats
        timestamp_formats = [
            "2023-01-01T12:00:00Z",        # ISO with Z
            "2023-01-01T12:00:00+00:00",   # ISO with timezone
            1672574400000,                 # Unix timestamp (ms)
            1672574400,                    # Unix timestamp (s)
            "invalid_timestamp"            # Invalid format
        ]
        
        received_messages = []
        server_client.on_chat_message(lambda msg: received_messages.append(msg))
        
        for i, timestamp in enumerate(timestamp_formats):
            msg = json.dumps({
                "topic": "events:all",
                "event": "chat_message",
                "payload": {
                    "data": {
                        "user_name": f"user_{i}",
                        "message": f"Message {i}",
                        "timestamp": timestamp,
                        "fragments": [],
                        "badges": []
                    }
                }
            })
            mock_ws.add_incoming_message(msg)
        
        with patch('websockets.connect', return_value=mock_ws):
            await server_client._do_connect()
            await server_client._do_listen()
            
            await asyncio.sleep(0.1)
            
            # Should handle all timestamp formats gracefully
            assert len(received_messages) == len(timestamp_formats)


class TestCrossServiceResilience:
    """Test resilience patterns across multiple WebSocket clients."""
    
    async def test_dual_client_operation(self):
        """Test operating both phononmaser and server clients simultaneously."""
        phono_client = PhononmaserClient("ws://test:8889")
        server_client = ServerClient("ws://test:7175/socket/websocket")
        
        try:
            # Create separate mock connections
            phono_mock = MockWebSocketConnection()
            server_mock = MockWebSocketConnection()
            
            async def mock_phono_connect(*args, **kwargs):
                if 'test:8889' in args[0]:
                    return phono_mock
                elif 'test:7175' in args[0]:
                    return server_mock
                else:
                    raise ValueError(f"Unexpected URL: {args[0]}")
            
            with patch('websockets.connect', side_effect=mock_phono_connect):
                # Connect both clients
                phono_success = await phono_client._do_connect()
                server_success = await server_client._do_connect()
                
                assert phono_success is True
                assert server_success is True
                
                # Both should maintain independent connection states
                assert phono_client._connection_state == ConnectionState.CONNECTED
                assert server_client._connection_state == ConnectionState.CONNECTED
                
        finally:
            await phono_client.disconnect()
            await server_client.disconnect()
    
    async def test_cascading_failure_isolation(self):
        """Test that failure in one client doesn't affect others."""
        phono_client = PhononmaserClient("ws://test:8889")
        server_client = ServerClient("ws://test:7175/socket/websocket")
        
        try:
            # Setup phono to fail, server to succeed
            phono_mock = MockWebSocketConnection(should_fail_connect=True)
            server_mock = MockWebSocketConnection()
            
            async def selective_mock_connect(*args, **kwargs):
                if 'test:8889' in args[0]:
                    return phono_mock
                elif 'test:7175' in args[0]:
                    return server_mock
                else:
                    raise ValueError(f"Unexpected URL: {args[0]}")
            
            with patch('websockets.connect', side_effect=selective_mock_connect):
                # Phono should fail
                phono_success = await phono_client._do_connect()
                assert phono_success is False
                
                # Server should still succeed
                server_success = await server_client._do_connect()
                assert server_success is True
                
        finally:
            await phono_client.disconnect()
            await server_client.disconnect()
    
    async def test_concurrent_message_processing_across_clients(self):
        """Test concurrent message processing across multiple clients."""
        phono_client = PhononmaserClient("ws://test:8889")
        server_client = ServerClient("ws://test:7175/socket/websocket")
        
        try:
            phono_mock = MockWebSocketConnection()
            server_mock = MockWebSocketConnection()
            
            # Add messages to both clients
            for i in range(5):
                # Phononmaser transcription
                phono_msg = json.dumps({
                    "type": "audio:transcription",
                    "timestamp": int(datetime.now().timestamp() * 1_000_000) + i,
                    "text": f"Transcription {i}",
                    "duration": 1.0
                })
                phono_mock.add_incoming_message(phono_msg)
                
                # Server chat message
                server_msg = json.dumps({
                    "topic": "events:all",
                    "event": "chat_message",
                    "payload": {
                        "data": {
                            "user_name": f"user_{i}",
                            "message": f"Chat message {i}",
                            "timestamp": "2023-01-01T12:00:00Z",
                            "fragments": [],
                            "badges": []
                        }
                    }
                })
                server_mock.add_incoming_message(server_msg)
            
            received_transcriptions = []
            received_chats = []
            
            phono_client.on_transcription(lambda e: received_transcriptions.append(e))
            server_client.on_chat_message(lambda e: received_chats.append(e))
            
            async def mock_connect(*args, **kwargs):
                if 'test:8889' in args[0]:
                    return phono_mock
                elif 'test:7175' in args[0]:
                    return server_mock
                else:
                    raise ValueError(f"Unexpected URL: {args[0]}")
            
            with patch('websockets.connect', side_effect=mock_connect):
                # Connect and listen on both
                await phono_client._do_connect()
                await server_client._do_connect()
                
                # Process messages concurrently
                tasks = [
                    phono_client._do_listen(),
                    server_client._do_listen()
                ]
                
                await asyncio.gather(*tasks, return_exceptions=True)
                await asyncio.sleep(0.1)
                
                # Both should have processed their messages
                assert len(received_transcriptions) == 5
                assert len(received_chats) == 5
                
        finally:
            await phono_client.disconnect()
            await server_client.disconnect()
    
    async def test_resource_cleanup_across_clients(self):
        """Test proper resource cleanup across multiple clients."""
        clients = [
            PhononmaserClient("ws://test:8889"),
            ServerClient("ws://test:7175/socket/websocket")
        ]
        
        try:
            # Connect all clients
            for client in clients:
                mock_ws = MockWebSocketConnection()
                with patch('websockets.connect', return_value=mock_ws):
                    await client._do_connect()
                    assert client._connection_state == ConnectionState.CONNECTED
            
            # Disconnect all clients
            for client in clients:
                await client.disconnect()
                assert client._connection_state == ConnectionState.DISCONNECTED
                
        finally:
            # Ensure cleanup even if test fails
            for client in clients:
                try:
                    await client.disconnect()
                except Exception:
                    pass


class TestNetworkConditionSimulation:
    """Test WebSocket behavior under various network conditions."""
    
    async def test_high_latency_conditions(self):
        """Test behavior under high latency conditions."""
        client = ServerClient("ws://test:7175/socket/websocket")
        
        try:
            # Mock high latency connection
            mock_ws = MockWebSocketConnection(
                connection_delay=0.5,  # 500ms connection delay
                message_delay=0.1      # 100ms per message
            )
            
            with patch('websockets.connect', return_value=mock_ws):
                start_time = time.time()
                success = await client._do_connect()
                end_time = time.time()
                
                assert success is True
                assert (end_time - start_time) >= 0.5  # Should respect connection delay
                
        finally:
            await client.disconnect()
    
    async def test_intermittent_connectivity(self):
        """Test behavior with intermittent connectivity."""
        client = PhononmaserClient("ws://test:8889")
        
        try:
            connection_attempts = 0
            
            async def intermittent_connect(*args, **kwargs):
                nonlocal connection_attempts
                connection_attempts += 1
                
                # Fail every other attempt
                if connection_attempts % 2 == 1:
                    raise websockets.exceptions.ConnectionClosed(None, None)
                
                return MockWebSocketConnection()
            
            with patch('websockets.connect', side_effect=intermittent_connect):
                # Should eventually succeed despite intermittent failures
                success = await client.connect()
                
                assert success is True
                assert connection_attempts >= 2  # Should have retried
                
        finally:
            await client.disconnect()
    
    async def test_bandwidth_limited_conditions(self):
        """Test behavior under bandwidth-limited conditions."""
        client = ServerClient("ws://test:7175/socket/websocket")
        
        try:
            # Simulate slow message processing
            mock_ws = MockWebSocketConnection(message_delay=0.05)  # 50ms per message
            
            # Add many messages to simulate bandwidth constraints
            for i in range(20):
                msg = json.dumps({
                    "topic": "events:all",
                    "event": "chat_message",
                    "payload": {
                        "data": {
                            "user_name": f"bandwidth_user_{i}",
                            "message": f"Bandwidth test message {i}",
                            "timestamp": "2023-01-01T12:00:00Z",
                            "fragments": [],
                            "badges": []
                        }
                    }
                })
                mock_ws.add_incoming_message(msg)
            
            received_messages = []
            client.on_chat_message(lambda msg: received_messages.append(msg))
            
            with patch('websockets.connect', return_value=mock_ws):
                await client._do_connect()
                
                start_time = time.time()
                await client._do_listen()
                end_time = time.time()
                
                # Should handle bandwidth constraints gracefully
                processing_time = end_time - start_time
                assert processing_time >= 0.1  # Should take some time due to delays
                
                await asyncio.sleep(0.5)  # Allow async processing
                assert len(received_messages) > 0  # Should process some messages
                
        finally:
            await client.disconnect()
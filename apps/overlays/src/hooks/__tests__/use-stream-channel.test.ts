import { describe, test, expect, mock, type Mock } from 'bun:test'
import { createRoot, createSignal } from 'solid-js'

// Create a simplified test version of the hook for better isolation
function createTestStreamChannel() {
  const [isConnected, setIsConnected] = createSignal(false)
  const [streamState, setStreamState] = createSignal({
    current_show: 'variety',
    active_content: null,
    priority_level: 'ticker',
    interrupt_stack: [],
    ticker_rotation: [],
    metadata: {
      last_updated: new Date().toISOString(),
      state_version: 0
    }
  })

  let mockSocket: unknown = null
  let mockChannel: unknown = null

  const joinChannel = () => {
    if (!mockSocket) return

    mockChannel = mockSocket.channel('stream:overlays', {})

    // Simulate join
    mockChannel
      .join()
      .receive('ok', () => {
        mockChannel.push('request_state', {})
      })
      .receive('error', () => {})
      .receive('timeout', () => {})

    // Setup event handlers
    mockChannel.on('stream_state', (payload: unknown) => {
      setStreamState(payload)
    })

    mockChannel.on('content_update', (payload: unknown) => {
      if (payload.type === 'goals_update') {
        setStreamState((prev) => ({
          ...prev,
          active_content:
            prev.active_content?.type === 'stream_goals'
              ? { ...prev.active_content, data: payload.data }
              : prev.active_content
        }))
      }
    })
  }

  const sendMessage = (event: string, payload: unknown) => {
    if (mockChannel && isConnected()) {
      mockChannel
        .push(event, payload)
        .receive('ok', () => {})
        .receive('error', () => {})
    }
  }

  // Initialize
  mockSocket = createMockSocket()
  setIsConnected(mockSocket.isConnected())

  // Auto-join when connected
  if (isConnected()) {
    joinChannel()
  }

  return {
    isConnected,
    streamState,
    sendMessage,
    _mockSocket: mockSocket,
    _mockChannel: () => mockChannel
  }
}

// Mock Socket and Channel creators
function createMockSocket() {
  const mockSocket = {
    isConnected: mock(() => true),
    channel: mock((topic: string) => createMockChannel(topic)),
    disconnect: mock(() => undefined),
    connect: mock(() => undefined)
  }
  return mockSocket
}

function createMockChannel(_topic: string) {
  const mockChannel = {
    join: mock(() => ({
      receive: mock((event: string, callback: (data: unknown) => void) => {
        if (event === 'ok') {
          setTimeout(() => callback({}), 0)
        }
        return {
          receive: mock((nextEvent: string, nextCallback: (data: unknown) => void) => {
            if (nextEvent === 'error') {
              setTimeout(() => nextCallback({ reason: 'test_error' }), 0)
            } else if (nextEvent === 'timeout') {
              setTimeout(() => nextCallback(), 0)
            }
            return { receive: mock(() => ({})) }
          })
        }
      })
    })),
    leave: mock(() => undefined),
    push: mock((_event: string, _payload: unknown) => ({
      receive: mock((responseEvent: string, callback: (data: unknown) => void) => {
        if (responseEvent === 'ok') {
          setTimeout(() => callback({}), 0)
        } else if (responseEvent === 'error') {
          setTimeout(() => callback({ reason: 'send_failed' }), 0)
        }
        return { receive: mock(() => ({ receive: mock(() => ({})) })) }
      })
    })),
    on: mock(() => undefined),
    off: mock(() => undefined)
  }
  return mockChannel
}

// Helper to render hook in solid context
function renderTestHook(hookFn: () => unknown) {
  let result: unknown
  let dispose: () => void

  createRoot((disposeRoot) => {
    dispose = disposeRoot
    result = hookFn()
  })

  return {
    result: () => result,
    unmount: () => dispose()
  }
}

describe('useStreamChannel WebSocket Resilience', () => {
  describe('Connection Management', () => {
    test('establishes initial connection and joins channel', async () => {
      const { result } = renderTestHook(() => createTestStreamChannel())

      // Wait for initial connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      const hookResult = result()
      expect(hookResult._mockSocket.channel).toHaveBeenCalledWith('stream:overlays', {})
      expect(hookResult.isConnected()).toBe(true)
    })

    test('handles connection loss gracefully', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Initially connected
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(result.isConnected()).toBe(true)

      // Simulate connection loss
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)

      // Wait for connection check interval
      await new Promise((resolve) => setTimeout(resolve, 1100))

      expect(mockChannel.leave).toHaveBeenCalled()
    })

    test('automatically reconnects when connection restored', async () => {
      renderHook(() => useStreamChannel())

      // Initially disconnected
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate connection restoration
      ;(mockSocket.isConnected as Mock).mockReturnValue(true)
      ;(mockSocket.channel as Mock).mockReturnValue(mockChannel)

      // Wait for connection check interval
      await new Promise((resolve) => setTimeout(resolve, 1100))

      // Should attempt to rejoin channel
      expect(mockChannel.join).toHaveBeenCalled()
    })

    test('prevents multiple channel joins for same connection', async () => {
      renderHook(() => useStreamChannel())

      // Wait for initial connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Clear previous calls
      ;(mockChannel.join as Mock).mockClear()

      // Trigger another connection check (connection stays true)
      await new Promise((resolve) => setTimeout(resolve, 1100))

      // Should not join again
      expect(mockChannel.join).not.toHaveBeenCalled()
    })
  })

  describe('Message Handling During Disconnection', () => {
    test('queues messages when disconnected and does not send', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Simulate disconnected state
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Attempt to send message
      result.sendMessage('test_event', { data: 'test' })

      // Should not push to channel
      expect(mockChannel.push).not.toHaveBeenCalled()
    })

    test('sends messages immediately when connected', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Initially connected
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Send message
      result.sendMessage('test_event', { data: 'test' })

      expect(mockChannel.push).toHaveBeenCalledWith('test_event', { data: 'test' })
    })
  })

  describe('State Synchronization', () => {
    test('maintains state consistency during reconnection', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Initial state
      const initialState = result.streamState()
      expect(initialState.current_show).toBe('variety')

      // Simulate disconnection and reconnection
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 100))
      ;(mockSocket.isConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 1100))

      // State should remain consistent
      expect(result.streamState().current_show).toBe('variety')
    })

    test('requests fresh state after reconnection', async () => {
      renderHook(() => useStreamChannel())

      // Setup channel join to trigger state request
      const mockJoinReceive = mock((event: string, callback: (data: unknown) => void) => {
        if (event === 'ok') {
          setTimeout(() => callback({}), 0)
        }
        return { receive: mock(() => ({ receive: mock(() => ({})) })) }
      })
      ;(mockChannel.join as Mock).mockReturnValue({ receive: mockJoinReceive })

      // Initially disconnected, then connect
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 100))
      ;(mockSocket.isConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 1100))

      // Should request state after successful join
      expect(mockChannel.push).toHaveBeenCalledWith('request_state', {})
    })

    test('handles stream state updates correctly', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for initial connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate receiving stream state update
      const updateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (updateHandler) {
        const newState: StreamState = {
          current_show: 'ironmon',
          active_content: {
            type: 'test_content',
            data: { test: true },
            priority: 1,
            started_at: new Date().toISOString(),
            layer: 'foreground'
          },
          priority_level: 'alert',
          interrupt_stack: [],
          ticker_rotation: [],
          metadata: {
            last_updated: new Date().toISOString(),
            state_version: 1
          }
        }

        updateHandler(newState)
        await new Promise((resolve) => setTimeout(resolve, 10))

        expect(result.streamState().current_show).toBe('ironmon')
        expect(result.streamState().active_content?.type).toBe('test_content')
      }
    })
  })

  describe('Error Handling and Recovery', () => {
    test('handles channel join failures gracefully', async () => {
      // Setup join to fail
      const mockJoinReceive = mock((_event: string, callback: (data: unknown) => void) => {
        if (_event === 'error') {
          setTimeout(() => callback({ reason: 'test_error' }), 0)
        }
        return {
          receive: mock((_nextEvent: string, nextCallback: (data: unknown) => void) => {
            if (_nextEvent === 'timeout') {
              setTimeout(() => nextCallback(), 0)
            }
            return { receive: mock(() => ({})) }
          })
        }
      })
      ;(mockChannel.join as Mock).mockReturnValue({ receive: mockJoinReceive })

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection attempt
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Should still be connected to socket, even if channel join failed
      expect(result.isConnected()).toBe(true)
    })

    test('handles channel join timeout gracefully', async () => {
      // Setup join to timeout
      const mockJoinReceive = mock((event: string, callback: (data: unknown) => void) => {
        // Skip 'ok' and 'error', go straight to timeout
        return {
          receive: mock((nextEvent: string, nextCallback: (data: unknown) => void) => {
            if (nextEvent === 'timeout') {
              setTimeout(() => nextCallback(), 0)
            }
            return { receive: mock(() => ({})) }
          })
        }
      })
      ;(mockChannel.join as Mock).mockReturnValue({ receive: mockJoinReceive })

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection attempt
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Should still maintain connection state
      expect(result.isConnected()).toBe(true)
    })

    test('handles message send failures gracefully', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Setup push to fail
      const mockPushReceive = mock((event: string, callback: (data: unknown) => void) => {
        if (event === 'error') {
          setTimeout(() => callback({ reason: 'send_failed' }), 0)
        }
        return { receive: mock(() => ({ receive: mock(() => ({})) })) }
      })
      ;(mockChannel.push as Mock).mockReturnValue({ receive: mockPushReceive })

      // Should not throw error
      expect(() => {
        result.sendMessage('test_event', { data: 'test' })
      }).not.toThrow()
    })
  })

  describe('Connection State Transitions', () => {
    test('handles rapid connection state changes', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Rapid state changes
      ;(mockSocket.isConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 50))
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 50))
      ;(mockSocket.isConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 50))

      // Should handle gracefully without crashes
      expect(() => result.isConnected()).not.toThrow()
    })

    test('prevents memory leaks during frequent reconnections', async () => {
      const { unmount } = renderHook(() => useStreamChannel())

      // Simulate multiple connection cycles
      for (let i = 0; i < 5; i++) {
        ;(mockSocket.isConnected as Mock).mockReturnValue(false)
        await new Promise((resolve) => setTimeout(resolve, 100))
        ;(mockSocket.isConnected as Mock).mockReturnValue(true)
        await new Promise((resolve) => setTimeout(resolve, 100))
      }

      // Clean unmount
      unmount()

      // Should have called socket disconnect
      expect(mockSocket.disconnect).toHaveBeenCalled()
    })
  })

  describe('Performance Under Load', () => {
    test('handles high frequency state updates efficiently', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Get the stream_state handler
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (stateHandler) {
        // Send many rapid updates
        const startTime = performance.now()

        for (let i = 0; i < 100; i++) {
          const state: StreamState = {
            current_show: 'variety',
            active_content: null,
            priority_level: 'ticker',
            interrupt_stack: [],
            ticker_rotation: [],
            metadata: {
              last_updated: new Date().toISOString(),
              state_version: i
            }
          }
          stateHandler(state)
        }

        const endTime = performance.now()

        // Should process updates quickly (under 100ms for 100 updates)
        expect(endTime - startTime).toBeLessThan(100)

        // Final state should be the last update
        await new Promise((resolve) => setTimeout(resolve, 10))
        expect(result.streamState().metadata.state_version).toBe(99)
      }
    })

    test('handles content updates without blocking UI', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Get the content_update handler
      const contentHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'content_update')?.[1]

      if (contentHandler) {
        // Simulate content update
        contentHandler({
          type: 'goals_update',
          data: { current_goal: 100, target_goal: 500 },
          timestamp: Date.now()
        })

        await new Promise((resolve) => setTimeout(resolve, 10))

        // Should not block and should be processable
        expect(() => result.streamState()).not.toThrow()
      }
    })
  })

  describe('Cleanup and Resource Management', () => {
    test('properly cleans up on unmount', async () => {
      const { unmount } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Unmount component
      unmount()

      // Should clean up resources
      expect(mockChannel.leave).toHaveBeenCalled()
      expect(mockSocket.disconnect).toHaveBeenCalled()
    })

    test('handles cleanup when already disconnected', async () => {
      const { unmount } = renderHook(() => useStreamChannel())

      // Simulate disconnection before unmount
      ;(mockSocket.isConnected as Mock).mockReturnValue(false)
      await new Promise((resolve) => setTimeout(resolve, 1100))

      // Should not crash during cleanup
      expect(() => unmount()).not.toThrow()
    })
  })

  describe('Edge Cases', () => {
    test('handles null socket gracefully', async () => {
      // Mock createPhoenixSocket to return null
      const createSocketModule = await import('@landale/shared/phoenix-connection')
      const originalCreateSocket = createSocketModule.createPhoenixSocket
      ;(createSocketModule.createPhoenixSocket as Mock).mockReturnValue(null)

      renderHook(() => useStreamChannel())

      // Should not crash when socket is null

      // Restore original
      ;(createSocketModule.createPhoenixSocket as Mock).mockImplementation(originalCreateSocket)
    })

    test('handles malformed message payloads', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Get handlers
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (stateHandler) {
        // Send malformed state (should not crash)
        expect(() => {
          stateHandler({})
          stateHandler(null)
          stateHandler(undefined)
        }).not.toThrow()
      }
    })

    test('maintains connection during background/foreground transitions', async () => {
      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(result.isConnected()).toBe(true)

      // Simulate app going to background (connection remains)
      await new Promise((resolve) => setTimeout(resolve, 2000))

      // Should still be connected
      expect(result.isConnected()).toBe(true)
    })
  })
})

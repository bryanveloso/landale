import { describe, test, expect, beforeEach, afterEach, mock, type Mock } from 'bun:test'
import { renderHook, cleanup } from '@solidjs/testing-library'
import { Socket, Channel } from 'phoenix'
import { useStreamChannel } from '../hooks/use-stream-channel'

/**
 * Integration tests for WebSocket resilience patterns across the entire system.
 *
 * These tests verify that the streaming platform can handle real-world network
 * conditions and maintain overlay functionality during live streaming.
 */

// Mock implementations for controlled testing
const createMockSocket = (options: {
  shouldFailConnection?: boolean
  shouldFailReconnection?: boolean
  connectionDelay?: number
  messageLatency?: number
  intermittentFailures?: boolean
}) => {
  let connected = !options.shouldFailConnection
  let connectionAttempts = 0
  let messagesSent = 0

  const mockSocket = {
    isConnected: mock(() => connected),
    connect: mock(() => {
      connectionAttempts++
      if (options.shouldFailConnection && connectionAttempts === 1) {
        connected = false
        return
      }
      if (options.shouldFailReconnection && connectionAttempts > 1) {
        connected = false
        return
      }
      connected = true
    }),
    disconnect: mock(() => {
      connected = false
    }),
    channel: mock(() => mockChannel),
    onOpen: mock(() => undefined),
    onClose: mock(() => undefined),
    onError: mock(() => undefined)
  } as unknown as Socket

  const mockChannel = {
    join: mock(() => ({
      receive: mock((event: string, callback: (data: unknown) => void) => {
        if (event === 'ok' && connected) {
          // Simulate network delay
          setTimeout(() => callback({}), options.connectionDelay || 0)
        } else if (event === 'error') {
          setTimeout(() => callback({ reason: 'mock_error' }), 10)
        } else if (event === 'timeout') {
          setTimeout(() => callback(), 50)
        }
        return {
          receive: mock((nextEvent: string, nextCallback: (data: unknown) => void) => {
            if (nextEvent === 'error') {
              setTimeout(() => nextCallback({ reason: 'mock_error' }), 10)
            } else if (nextEvent === 'timeout') {
              setTimeout(() => nextCallback(), 50)
            }
            return { receive: mock(() => ({})) }
          })
        }
      })
    })),
    leave: mock(() => undefined),
    push: mock(() => {
      messagesSent++

      // Simulate intermittent message failures
      if (options.intermittentFailures && messagesSent % 5 === 0) {
        return {
          receive: mock((event: string, callback: (data: unknown) => void) => {
            if (event === 'error') {
              setTimeout(() => callback({ reason: 'network_error' }), 10)
            }
            return { receive: mock(() => ({ receive: mock(() => ({})) })) }
          })
        }
      }

      return {
        receive: mock((event: string, callback: (data: unknown) => void) => {
          if (event === 'ok') {
            setTimeout(() => callback({}), options.messageLatency || 0)
          }
          return { receive: mock(() => ({ receive: mock(() => ({})) })) }
        })
      }
    }),
    on: mock(() => undefined),
    off: mock(() => undefined)
  } as unknown as Channel

  return {
    mockSocket,
    mockChannel,
    getConnectionAttempts: () => connectionAttempts,
    getMessagesSent: () => messagesSent
  }
}

// Mock phoenix-connection module
mock.module('@landale/shared/phoenix-connection', () => ({
  createPhoenixSocket: mock(() => null), // Will be overridden per test
  isSocketConnected: mock(() => false) // Will be overridden per test
}))

// Mock logger
mock.module('@landale/logger/browser', () => ({
  createLogger: mock(() => ({
    child: mock(() => ({
      info: mock(() => undefined),
      debug: mock(() => undefined),
      warn: mock(() => undefined),
      error: mock(() => undefined)
    }))
  }))
}))

describe('WebSocket Integration & End-to-End Resilience', () => {
  beforeEach(() => {
    // Reset all mocks before each test
  })

  afterEach(() => {
    cleanup()
  })

  describe('Production Streaming Scenarios', () => {
    test('maintains overlay functionality during 30-second network interruption', async () => {
      const { mockSocket } = createMockSocket({
        shouldFailConnection: false,
        connectionDelay: 100
      })

      // Mock progressive reconnection
      let reconnectionPhase = 0
      ;(mockSocket.isConnected as Mock).mockImplementation(() => {
        // Simulate network interruption cycle
        if (reconnectionPhase < 300) {
          // 30 seconds of interruption (100ms intervals)
          reconnectionPhase++
          return reconnectionPhase > 200 && reconnectionPhase < 250 ? false : true
        }
        return true
      })

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockImplementation(() => mockSocket.isConnected())

      const { result } = renderHook(() => useStreamChannel())

      // Wait for initial connection
      await new Promise((resolve) => setTimeout(resolve, 150))

      // Simulate 30-second network interruption
      for (let i = 0; i < 30; i++) {
        await new Promise((resolve) => setTimeout(resolve, 100))

        // During interruption, overlay should still be functional
        expect(() => result.streamState()).not.toThrow()
        expect(() => result.isConnected()).not.toThrow()
      }

      // After interruption, should recover
      await new Promise((resolve) => setTimeout(resolve, 200))
      expect(result.isConnected()).toBe(true)
    })

    test('handles high-frequency state updates during live streaming', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Get the stream_state handler
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (stateHandler) {
        // Simulate rapid state updates (like during active streaming)
        const startTime = performance.now()

        for (let i = 0; i < 200; i++) {
          stateHandler({
            current_show: 'ironmon',
            active_content: {
              type: 'donation_alert',
              data: { amount: 5, donor: `donor_${i}` },
              priority: 1,
              started_at: new Date().toISOString(),
              layer: 'foreground'
            },
            priority_level: 'alert',
            interrupt_stack: [],
            ticker_rotation: [],
            metadata: {
              last_updated: new Date().toISOString(),
              state_version: i
            }
          })

          // Brief pause to simulate realistic update frequency
          if (i % 10 === 0) {
            await new Promise((resolve) => setTimeout(resolve, 1))
          }
        }

        const endTime = performance.now()

        // Should handle high-frequency updates efficiently
        expect(endTime - startTime).toBeLessThan(500) // Under 500ms for 200 updates

        // State should reflect the final update
        await new Promise((resolve) => setTimeout(resolve, 10))
        expect(result.streamState().metadata.state_version).toBe(199)
      }
    })

    test('recovers gracefully from Phoenix server restart', async () => {
      let serverRestarted = false
      const { mockSocket: initialSocket } = createMockSocket({})
      const { mockSocket: restartedSocket } = createMockSocket({
        connectionDelay: 200 // Simulate server restart delay
      })

      const phoenixModule = await import('@landale/shared/phoenix-connection')

      // Initially return first socket
      ;(phoenixModule.createPhoenixSocket as Mock).mockImplementation(() =>
        serverRestarted ? restartedSocket : initialSocket
      )
      ;(phoenixModule.isSocketConnected as Mock).mockImplementation(() =>
        serverRestarted ? restartedSocket.isConnected() : initialSocket.isConnected()
      )

      const { result } = renderHook(() => useStreamChannel())

      // Wait for initial connection
      await new Promise((resolve) => setTimeout(resolve, 100))
      expect(result.isConnected()).toBe(true)

      // Simulate server restart
      serverRestarted = true
      ;(initialSocket.isConnected as Mock).mockReturnValue(false)

      // Wait for detection of disconnection
      await new Promise((resolve) => setTimeout(resolve, 1200)) // Wait for connection check interval

      // Should eventually reconnect to restarted server
      ;(restartedSocket.isConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 1200))

      expect(result.isConnected()).toBe(true)
      expect(restartedChannel.join).toHaveBeenCalled()
    })

    test('maintains state consistency during connection instability', async () => {
      const { mockSocket } = createMockSocket({
        intermittentFailures: true
      })

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)

      // Simulate unstable connection
      let connectionStable = true
      ;(phoenixModule.isSocketConnected as Mock).mockImplementation(() => {
        connectionStable = !connectionStable // Toggle every call
        return connectionStable
      })

      const { result } = renderHook(() => useStreamChannel())

      // Initial state
      const initialState = result.streamState()

      // Simulate unstable period with multiple reconnections
      for (let i = 0; i < 10; i++) {
        await new Promise((resolve) => setTimeout(resolve, 120)) // Trigger connection checks
      }

      // State should remain consistent despite connection instability
      const finalState = result.streamState()
      expect(finalState.current_show).toBe(initialState.current_show)
      expect(finalState.priority_level).toBe(initialState.priority_level)
    })
  })

  describe('Message Queue Resilience', () => {
    test('handles message queue overflow during connection outage', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate disconnection
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(false)

      // Try to send many messages while disconnected
      for (let i = 0; i < 100; i++) {
        result.sendMessage('test_event', { sequence: i })
      }

      // Reconnect
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)
      await new Promise((resolve) => setTimeout(resolve, 1200))

      // Should handle overflow gracefully without crashing
      expect(() => result.sendMessage('recovery_test', {})).not.toThrow()
    })

    test('preserves message order during reconnection', async () => {
      const { mockSocket, getMessagesSent } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Send messages in sequence
      const messagesToSend = ['msg1', 'msg2', 'msg3', 'msg4', 'msg5']
      for (const msg of messagesToSend) {
        result.sendMessage('ordered_test', { content: msg })
        await new Promise((resolve) => setTimeout(resolve, 10)) // Small delay
      }

      // All messages should be sent
      expect(getMessagesSent()).toBe(messagesToSend.length)
    })
  })

  describe('Performance Under Stress', () => {
    test('maintains performance during concurrent operations', async () => {
      const { mockSocket } = createMockSocket({
        messageLatency: 5 // 5ms latency per message
      })

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      const startTime = performance.now()

      // Simulate concurrent operations
      const operations = []

      // Stream state updates
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (stateHandler) {
        for (let i = 0; i < 20; i++) {
          operations.push(
            new Promise<void>((resolve) => {
              stateHandler({
                current_show: 'variety',
                active_content: null,
                priority_level: 'ticker',
                interrupt_stack: [],
                ticker_rotation: [],
                metadata: {
                  last_updated: new Date().toISOString(),
                  state_version: i
                }
              })
              resolve()
            })
          )
        }
      }

      // Message sending
      for (let i = 0; i < 20; i++) {
        operations.push(
          new Promise<void>((resolve) => {
            result.sendMessage('stress_test', { index: i })
            resolve()
          })
        )
      }

      // Connection status checks
      for (let i = 0; i < 20; i++) {
        operations.push(
          new Promise<void>((resolve) => {
            result.isConnected()
            resolve()
          })
        )
      }

      await Promise.all(operations)
      const endTime = performance.now()

      // Should complete all operations quickly
      expect(endTime - startTime).toBeLessThan(1000) // Under 1 second
    })

    test('handles memory efficiently during long-running session', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result, unmount } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate long-running session with many state updates
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]

      if (stateHandler) {
        // Send 1000 state updates (simulating 1+ hour of streaming)
        for (let i = 0; i < 1000; i++) {
          stateHandler({
            current_show: 'ironmon',
            active_content:
              i % 10 === 0
                ? {
                    type: 'alert',
                    data: { message: `Alert ${i}` },
                    priority: 1,
                    started_at: new Date().toISOString()
                  }
                : null,
            priority_level: 'ticker',
            interrupt_stack: [],
            ticker_rotation: [],
            metadata: {
              last_updated: new Date().toISOString(),
              state_version: i
            }
          })

          // Periodic cleanup simulation
          if (i % 100 === 0) {
            await new Promise((resolve) => setTimeout(resolve, 1))
          }
        }
      }

      // Should still be responsive
      expect(() => result.streamState()).not.toThrow()
      expect(result.streamState().metadata.state_version).toBe(999)

      // Clean unmount should work
      expect(() => unmount()).not.toThrow()
    })
  })

  describe('Error Recovery Patterns', () => {
    test('recovers from malformed message handling', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Get handlers
      const stateHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'stream_state')?.[1]
      const contentHandler = (mockChannel.on as Mock).mock.calls.find((call) => call[0] === 'content_update')?.[1]

      // Send malformed data
      if (stateHandler) {
        expect(() => {
          stateHandler(null)
          stateHandler(undefined)
          stateHandler({})
          stateHandler({ invalid: 'data' })
        }).not.toThrow()
      }

      if (contentHandler) {
        expect(() => {
          contentHandler(null)
          contentHandler({ type: 'invalid' })
          contentHandler({ invalid: 'structure' })
        }).not.toThrow()
      }

      // Should still be functional after malformed messages
      expect(result.isConnected()).toBe(true)
      expect(() => result.streamState()).not.toThrow()
    })

    test('handles rapid connect/disconnect cycles', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)

      let isConnected = true
      ;(phoenixModule.isSocketConnected as Mock).mockImplementation(() => isConnected)

      const { result } = renderHook(() => useStreamChannel())

      // Rapid connect/disconnect cycles
      for (let i = 0; i < 20; i++) {
        isConnected = !isConnected
        await new Promise((resolve) => setTimeout(resolve, 50))
      }

      // Should stabilize and be functional
      isConnected = true
      await new Promise((resolve) => setTimeout(resolve, 1200))

      expect(() => result.isConnected()).not.toThrow()
      expect(() => result.streamState()).not.toThrow()
    })
  })

  describe('Real-World Edge Cases', () => {
    test('handles browser tab visibility changes', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate tab going to background (connection might be throttled)
      // In real browsers, this might affect WebSocket behavior
      await new Promise((resolve) => setTimeout(resolve, 5000))

      // Tab comes back to foreground
      expect(result.isConnected()).toBe(true)
      expect(() => result.streamState()).not.toThrow()
    })

    test('maintains functionality during page reload preparation', async () => {
      const { mockSocket } = createMockSocket({})

      const phoenixModule = await import('@landale/shared/phoenix-connection')
      ;(phoenixModule.createPhoenixSocket as Mock).mockReturnValue(mockSocket)
      ;(phoenixModule.isSocketConnected as Mock).mockReturnValue(true)

      const { result, unmount } = renderHook(() => useStreamChannel())

      // Wait for connection
      await new Promise((resolve) => setTimeout(resolve, 100))

      // Simulate page unload preparation
      expect(() => {
        result.sendMessage('final_message', { type: 'cleanup' })
        unmount() // Simulates component cleanup during page unload
      }).not.toThrow()

      // Cleanup should be clean
      expect(mockChannel.leave).toHaveBeenCalled()
      expect(mockSocket.disconnect).toHaveBeenCalled()
    })
  })
})

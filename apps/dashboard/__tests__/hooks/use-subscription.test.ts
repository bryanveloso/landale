import { describe, it, expect, mock, beforeEach, afterEach } from 'bun:test'
import { renderHook, act } from '@testing-library/react'
import { useSubscription } from '@/hooks/use-subscription'

// Create mock functions
const mockSubscribe = mock()
const mockUnsubscribe = mock()

// Mock the trpc client module
import.meta.mock('@/lib/trpc-client', () => ({
  trpcClient: {
    twitch: {
      onMessage: {
        subscribe: mockSubscribe
      }
    },
    health: {
      check: {
        subscribe: mockSubscribe
      }
    }
  }
}))

describe('useSubscription', () => {
  beforeEach(() => {
    mockSubscribe.mockClear()
    mockUnsubscribe.mockClear()
  })

  it('should establish subscription and handle data', () => {
    const mockData = { message: 'test', timestamp: Date.now() }
    mockSubscribe.mockImplementation((_, options: { onData: (data: unknown) => void }) => {
      // Simulate immediate data callback
      setTimeout(() => options.onData(mockData), 0)
      return { unsubscribe: mockUnsubscribe }
    })

    const onData = mock()
    const { result } = renderHook(() => 
      useSubscription(['twitch', 'onMessage'], onData)
    )

    // Verify subscription was created
    expect(mockSubscribe).toHaveBeenCalled()
    expect(result.current.isConnected).toBe(true)

    // Verify data handler works
    act(() => {
      const subscribeCall = mockSubscribe.mock.calls[0]
      const options = subscribeCall[1]
      options.onData(mockData)
    })

    expect(onData).toHaveBeenCalledWith(mockData)
  })

  it('should handle errors gracefully', () => {
    const mockError = new Error('Connection failed')
    mockSubscribe.mockImplementation((_, options: { onError: (error: Error) => void }) => {
      setTimeout(() => options.onError(mockError), 0)
      return { unsubscribe: mockUnsubscribe }
    })

    const onError = mock()
    const { result } = renderHook(() => 
      useSubscription(['health', 'check'], undefined, { onError })
    )

    // Simulate error
    act(() => {
      const subscribeCall = mockSubscribe.mock.calls[0]
      const options = subscribeCall[1]
      options.onError(mockError)
    })

    expect(onError).toHaveBeenCalledWith(mockError)
    expect(result.current.error).toBe(mockError)
    expect(result.current.isConnected).toBe(false)
  })

  it('should cleanup subscription on unmount', () => {
    mockSubscribe.mockReturnValue({ unsubscribe: mockUnsubscribe })

    const { unmount } = renderHook(() => 
      useSubscription(['twitch', 'onMessage'])
    )

    expect(mockSubscribe).toHaveBeenCalled()

    unmount()

    expect(mockUnsubscribe).toHaveBeenCalled()
  })

  it('should handle reconnection', () => {
    mockSubscribe.mockReturnValue({ unsubscribe: mockUnsubscribe })

    const { result, rerender } = renderHook(() => 
      useSubscription(['twitch', 'onMessage'])
    )

    // Initial connection
    expect(result.current.isConnected).toBe(true)

    // Simulate disconnection
    act(() => {
      result.current.reconnect()
    })

    // Should unsubscribe and resubscribe
    expect(mockUnsubscribe).toHaveBeenCalled()
    expect(mockSubscribe).toHaveBeenCalledTimes(2)
  })
})
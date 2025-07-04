import '../setup'
import { describe, it, expect, mock, beforeEach, afterEach } from 'bun:test'
import { renderHook, act } from '@testing-library/react'

// Create mock functions
const mockSubscribe = mock()
const mockUnsubscribe = mock()

// Mock module before importing
mock.module('@/lib/trpc-client', () => ({
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
    },
    processes: {
      onStatusUpdate: {
        subscribe: mockSubscribe
      }
    }
  }
}))

// Import after mocking
const { useSubscription } = await import('@/hooks/use-subscription')

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
      useSubscription('twitch.onMessage', undefined, { onData })
    )

    // Verify subscription was created
    expect(mockSubscribe).toHaveBeenCalled()

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
      useSubscription('health.check', undefined, { onError })
    )

    // Simulate error
    act(() => {
      const subscribeCall = mockSubscribe.mock.calls[0]
      const options = subscribeCall[1]
      options.onError(mockError)
    })

    expect(onError).toHaveBeenCalledWith(mockError)
    expect(result.current.error).toBe(mockError)
  })

  it('should cleanup subscription on unmount', () => {
    mockSubscribe.mockReturnValue({ unsubscribe: mockUnsubscribe })

    const { unmount } = renderHook(() => 
      useSubscription('twitch.onMessage')
    )

    expect(mockSubscribe).toHaveBeenCalled()

    unmount()

    expect(mockUnsubscribe).toHaveBeenCalled()
  })

  it('should handle reconnection', () => {
    mockSubscribe.mockReturnValue({ unsubscribe: mockUnsubscribe })

    const { result, rerender } = renderHook(() => 
      useSubscription('twitch.onMessage')
    )

    // Initial connection
    expect(mockSubscribe).toHaveBeenCalledTimes(1)

    // Simulate disconnection
    act(() => {
      result.current.reset()
    })

    // Should unsubscribe and resubscribe
    expect(mockUnsubscribe).toHaveBeenCalled()
    expect(mockSubscribe).toHaveBeenCalledTimes(2)
  })

  it('should re-subscribe when input parameters change', () => {
    mockSubscribe.mockReturnValue({ unsubscribe: mockUnsubscribe })

    const { result, rerender } = renderHook(
      ({ machine }) => useSubscription('processes.onStatusUpdate', { machine }),
      { initialProps: { machine: 'zelan' } }
    )

    // Initial subscription
    expect(mockSubscribe).toHaveBeenCalledTimes(1)
    expect(mockSubscribe).toHaveBeenCalledWith({ machine: 'zelan' }, expect.any(Object))

    // Change the machine parameter
    rerender({ machine: 'demi' })

    // Should unsubscribe from old and subscribe to new
    expect(mockUnsubscribe).toHaveBeenCalledTimes(1)
    expect(mockSubscribe).toHaveBeenCalledTimes(2)
    expect(mockSubscribe).toHaveBeenLastCalledWith({ machine: 'demi' }, expect.any(Object))
  })
})
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useSubscription } from '@/hooks/use-subscription'
import { trpcClient } from '@/lib/trpc-client'

// Mock the trpc client
vi.mock('@/lib/trpc-client', () => ({
  trpcClient: {
    twitch: {
      onMessage: {
        subscribe: vi.fn()
      }
    },
    health: {
      check: {
        subscribe: vi.fn()
      }
    }
  }
}))

describe('useSubscription', () => {
  // Add timer mocks for better control
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })
  let mockUnsubscribe: () => void

  beforeEach(() => {
    mockUnsubscribe = vi.fn()
    vi.clearAllMocks()
  })

  it('should establish subscription and handle data', () => {
    const mockData = { message: 'test', timestamp: Date.now() }
    const mockSubscribe = vi.fn((_, options: { onData: (data: unknown) => void }) => {
      // Simulate async data emission
      setTimeout(() => {
        options.onData(mockData)
      }, 10)
      return { unsubscribe: mockUnsubscribe }
    })

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(trpcClient.health.check.subscribe as any) = mockSubscribe

    const { result } = renderHook(() => useSubscription('health.check', undefined))

    expect(result.current.isConnected).toBe(false)
    expect(result.current.data).toBeNull()

    // Advance timers to trigger the data callback
    act(() => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.data).toEqual(mockData)
    expect(result.current.isConnected).toBe(true)
  })

  it('should handle connection errors', () => {
    const testError = new Error('Connection failed')
    const mockSubscribe = vi.fn((_, options: { onError: (error: Error) => void }) => {
      // Simulate error after a short delay
      setTimeout(() => {
        options.onError(testError)
      }, 10)
      return { unsubscribe: mockUnsubscribe }
    })

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(trpcClient.health.check.subscribe as any) = mockSubscribe

    const { result } = renderHook(() =>
      useSubscription('health.check', undefined, {
        maxRetries: 0 // Disable retries for simplicity
      })
    )

    // Should start in connecting state
    expect(result.current.connectionState.state).toBe('connecting')

    // Advance timers to trigger the error
    act(() => {
      vi.advanceTimersByTime(20)
    })

    // Should now be in error state
    expect(result.current.error).toEqual(testError)
    expect(result.current.isConnected).toBe(false)
    expect(result.current.connectionState.state).toBe('error')
  })

  it('should cleanup subscription on unmount', () => {
    const mockSubscribe = vi.fn(() => ({ unsubscribe: mockUnsubscribe }))
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(trpcClient.health.check.subscribe as any) = mockSubscribe

    const { unmount } = renderHook(() => useSubscription('health.check', undefined))

    expect(mockSubscribe).toHaveBeenCalledTimes(1)

    unmount()

    expect(mockUnsubscribe).toHaveBeenCalledTimes(1)
  })

  it('should handle changing inputs', () => {
    const mockSubscribe = vi.fn((input: unknown, options: { onData: (data: unknown) => void }) => {
      setTimeout(() => {
        options.onData({ input })
      }, 10)
      return { unsubscribe: mockUnsubscribe }
    })

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(trpcClient.twitch.onMessage.subscribe as any) = mockSubscribe

    const { result, rerender } = renderHook(({ channel }) => useSubscription('twitch.onMessage', { channel }), {
      initialProps: { channel: 'channel1' }
    })

    // Advance timers to deliver the data
    act(() => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.data).toEqual({ input: { channel: 'channel1' } })

    // Change input
    rerender({ channel: 'channel2' })

    // Should unsubscribe from old and create new subscription
    expect(mockUnsubscribe).toHaveBeenCalled()
    // Check that we have more than initial call (React strict mode may cause extra calls)
    expect(mockSubscribe.mock.calls.length).toBeGreaterThan(1)

    // Advance timers for new data
    act(() => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.data).toEqual({ input: { channel: 'channel2' } })
  })

  it('should schedule retry on error', () => {
    const mockSubscribe = vi.fn((_, options: { onError: (error: Error) => void }) => {
      setTimeout(() => {
        options.onError(new Error('Failed'))
      }, 10)
      return { unsubscribe: mockUnsubscribe }
    })

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(trpcClient.health.check.subscribe as any) = mockSubscribe

    const { result } = renderHook(() =>
      useSubscription('health.check', undefined, {
        initialRetryDelay: 1000,
        maxRetries: 3
      })
    )

    // Initial subscription
    expect(mockSubscribe).toHaveBeenCalledTimes(1)

    // Trigger the error
    act(() => {
      vi.advanceTimersByTime(20)
    })

    // Should be in reconnecting state
    expect(result.current.connectionState.state).toBe('reconnecting')
    expect(result.current.connectionState.retryCount).toBe(1)
    expect(result.current.connectionState.nextRetryIn).toBe(1000)
  })
})

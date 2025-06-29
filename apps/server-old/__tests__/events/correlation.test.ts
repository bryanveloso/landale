import { describe, it, expect, beforeEach, mock, spyOn, type Mock } from 'bun:test'
import * as eventModule from '@/events'

// Create a mock for nanoid
const mockNanoid = mock(() => 'generated-correlation-id')

// Mock the nanoid module
await mock.module('nanoid', () => ({
  nanoid: mockNanoid
}))

describe('Event Correlation ID', () => {
  let mockEmit: Mock<(event: string, data: unknown) => Promise<void>>

  beforeEach(() => {
    mockNanoid.mockClear()

    // Spy on the eventEmitter.emit method
    mockEmit = spyOn(eventModule.eventEmitter, 'emit').mockImplementation(() => Promise.resolve())
  })

  describe('emitEventWithCorrelation', () => {
    it('should use provided correlation ID', async () => {
      const testData = {
        userId: '123',
        userName: 'testuser',
        userDisplayName: 'TestUser',
        color: '#FF0000',
        badges: {},
        badgeInfo: new Map(),
        emotes: [],
        bits: 0,
        cheer: null,
        isRedemption: false,
        rewardId: null,
        isFirst: false,
        isReturningChatter: false,
        messageText: 'Test message',
        messageType: 'text' as const
      }
      const correlationId = 'provided-correlation-id'

      await eventModule.emitEventWithCorrelation('twitch:message', testData, correlationId)

      expect(mockEmit).toHaveBeenCalledWith(
        'twitch:message',
        expect.objectContaining({
          userId: '123',
          messageText: 'Test message',
          correlationId: 'provided-correlation-id',
          timestamp: expect.any(String) as string
        })
      )
    })

    it('should generate correlation ID when not provided', async () => {
      const testData = {
        userId: '456',
        userName: 'cheerer',
        userDisplayName: 'Cheerer',
        bits: 100,
        message: 'PogChamp100'
      }

      await eventModule.emitEventWithCorrelation('twitch:cheer', testData)

      expect(mockEmit).toHaveBeenCalledWith(
        'twitch:cheer',
        expect.objectContaining({
          userId: '456',
          bits: 100,
          correlationId: 'generated-correlation-id',
          timestamp: expect.any(String) as string
        })
      )
      expect(mockNanoid).toHaveBeenCalled()
    })

    it('should add timestamp to all events', async () => {
      const testData = {
        type: 'init' as const,
        metadata: {
          version: '1.0.0',
          game: 2 // Emerald
        },
        source: 'tcp' as const
      }
      const beforeTime = Date.now()

      await eventModule.emitEventWithCorrelation('ironmon:init', testData, 'test-id')

      const afterTime = Date.now()

      expect(mockEmit).toHaveBeenCalledWith(
        'ironmon:init',
        expect.objectContaining({
          type: 'init',
          source: 'tcp',
          correlationId: 'test-id',
          timestamp: expect.any(String) as string
        })
      )

      // Verify timestamp is valid and within range
      const calls = mockEmit.mock.calls as Array<
        [string, { timestamp: string; correlationId: string; active?: boolean; type?: string; source?: string }]
      >
      const call = calls[0]
      if (!call) throw new Error('No call recorded')
      const eventData = call[1]
      const timestamp = eventData.timestamp
      const timestampMs = new Date(timestamp).getTime()

      // Verify it's a valid ISO string
      expect(new Date(timestamp).toISOString()).toBe(timestamp)

      // Verify timestamp is within the expected range (with 1ms tolerance)
      expect(timestampMs).toBeGreaterThanOrEqual(beforeTime - 1)
      expect(timestampMs).toBeLessThanOrEqual(afterTime + 1)
    })

    it('should handle undefined data gracefully', async () => {
      await eventModule.emitEventWithCorrelation('emoteRain:clear', undefined, 'clear-id')

      expect(mockEmit).toHaveBeenCalledWith(
        'emoteRain:clear',
        expect.objectContaining({
          correlationId: 'clear-id',
          timestamp: expect.any(String) as string
        })
      )
    })
  })
})

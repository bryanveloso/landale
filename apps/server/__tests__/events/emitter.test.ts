import { describe, it, expect, beforeEach, mock } from 'bun:test'
import type { EventMap } from '@/events/types'
import Emittery from 'emittery'
import type { z } from 'zod'

describe('EventEmitter', () => {
  let emitter: Emittery<EventMap>

  beforeEach(() => {
    // Create a new instance for each test to avoid state pollution
    emitter = new Emittery<EventMap>()
  })

  it('should emit and listen to typed events', async () => {
    const mockHandler = mock()

    emitter.on('twitch:follow', mockHandler)

    const followEvent = {
      userId: '123',
      userName: 'testuser',
      userDisplayName: 'TestUser',
      followDate: new Date()
    }

    await emitter.emit('twitch:follow', followEvent)

    expect(mockHandler).toHaveBeenCalledWith(followEvent)
    expect(mockHandler).toHaveBeenCalledTimes(1)
  })

  it('should handle multiple listeners for same event', async () => {
    const handler1 = mock()
    const handler2 = mock()

    emitter.on('twitch:cheer', handler1)
    emitter.on('twitch:cheer', handler2)

    const cheerEvent = {
      userId: '123',
      userName: 'testuser',
      userDisplayName: 'TestUser',
      bits: 100,
      message: 'Test cheer!'
    }

    await emitter.emit('twitch:cheer', cheerEvent)

    expect(handler1).toHaveBeenCalledWith(cheerEvent)
    expect(handler2).toHaveBeenCalledWith(cheerEvent)
  })

  it('should remove listeners correctly', async () => {
    const handler = mock()

    const unsubscribe = emitter.on('twitch:subscription', handler)

    const subEvent = {
      userId: '123',
      userName: 'testuser',
      userDisplayName: 'TestUser',
      tier: '1000' as const,
      isGift: false,
      cumulativeMonths: 1,
      streakMonths: 1,
      message: null
    }

    await emitter.emit('twitch:subscription', subEvent)
    expect(handler).toHaveBeenCalledTimes(1)

    unsubscribe()

    await emitter.emit('twitch:subscription', subEvent)
    expect(handler).toHaveBeenCalledTimes(1) // Still 1, not called again
  })

  it('should handle display events', async () => {
    const handler = mock()
    
    emitter.on('display:update', handler)

    const displayUpdate = {
      displayId: 'statusBar',
      data: { text: 'Test Status' }
    } as z.infer<(typeof EventMap)['display:update']>

    await emitter.emit('display:update', displayUpdate)

    expect(handler).toHaveBeenCalledWith(displayUpdate)
  })

  it('should handle once listeners', async () => {
    const handler = mock()

    emitter.once('twitch:raid').then(handler)

    const raidEvent = {
      userId: '123',
      userName: 'raider',
      userDisplayName: 'Raider',
      viewerCount: 50
    }

    await emitter.emit('twitch:raid', raidEvent)
    await emitter.emit('twitch:raid', raidEvent)

    expect(handler).toHaveBeenCalledTimes(1)
  })
})
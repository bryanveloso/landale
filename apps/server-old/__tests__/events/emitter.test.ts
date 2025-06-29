import { describe, it, expect, beforeEach, mock } from 'bun:test'
import type { EventMap } from '@/events/types'
import Emittery from 'emittery'

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
    
    emitter.on('display:statusBar:update' as keyof EventMap, handler)

    const displayUpdate = {
      displayId: 'statusBar',
      data: { text: 'Test Status' }
    }

    await emitter.emit('display:statusBar:update' as keyof EventMap, displayUpdate)

    expect(handler).toHaveBeenCalledWith(displayUpdate)
  })

  it('should handle once listeners', async () => {
    const handler = mock()

    void emitter.once('twitch:cheer').then(handler)

    const cheerEvent = {
      userId: '123',
      userName: 'cheerer',
      userDisplayName: 'Cheerer',
      bits: 100,
      message: 'Test cheer'
    }

    await emitter.emit('twitch:cheer', cheerEvent)
    await emitter.emit('twitch:cheer', cheerEvent)

    expect(handler).toHaveBeenCalledTimes(1)
  })
})
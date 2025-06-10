import { describe, it, expect, beforeEach, vi } from 'vitest'
import { eventEmitter } from '@/events/emitter'
import type { EventMap } from '@/events/types'
import Emittery from 'emittery'

describe('EventEmitter', () => {
  let emitter: Emittery<EventMap>

  beforeEach(() => {
    // Create a new instance for each test to avoid state pollution
    emitter = new Emittery<EventMap>()
  })

  it('should emit and listen to typed events', async () => {
    const mockHandler = vi.fn()
    
    emitter.on('twitch:follow', mockHandler)
    
    const followEvent = {
      userId: '123',
      userName: 'testuser',
      userDisplayName: 'TestUser',
      followedAt: new Date()
    }
    
    await emitter.emit('twitch:follow', followEvent)
    
    expect(mockHandler).toHaveBeenCalledWith(followEvent)
    expect(mockHandler).toHaveBeenCalledTimes(1)
  })

  it('should handle multiple listeners for same event', async () => {
    const handler1 = vi.fn()
    const handler2 = vi.fn()
    
    emitter.on('twitch:cheer', handler1)
    emitter.on('twitch:cheer', handler2)
    
    const cheerEvent = {
      userId: '123',
      userName: 'testuser',
      userDisplayName: 'TestUser',
      message: 'Great stream!',
      bits: 100,
      isAnonymous: false
    }
    
    await emitter.emit('twitch:cheer', cheerEvent)
    
    expect(handler1).toHaveBeenCalledWith(cheerEvent)
    expect(handler2).toHaveBeenCalledWith(cheerEvent)
  })

  it('should remove listeners with off()', async () => {
    const handler = vi.fn()
    
    emitter.on('ironmon:init', handler)
    emitter.off('ironmon:init', handler)
    
    await emitter.emit('ironmon:init', {
      gameId: 1,
      romName: 'Pokemon Emerald',
      seed: '12345',
      trainerId: 67890,
      secretId: 12345,
      username: 'Player'
    })
    
    expect(handler).not.toHaveBeenCalled()
  })

  it('should handle display update events', async () => {
    const handler = vi.fn()
    
    emitter.on('display:statusBar:update', handler)
    
    const display = {
      id: 'statusBar',
      schema: {} as any,
      data: {
        mode: 'game' as const,
        text: 'Playing Pokemon',
        isVisible: true,
        position: 'bottom' as const
      },
      metadata: {}
    }
    
    await emitter.emit('display:statusBar:update', display)
    
    expect(handler).toHaveBeenCalledWith(display)
  })

  it('should support once() for single-use listeners', async () => {
    const handler = vi.fn()
    
    // Emittery uses a different API for once
    const unsubscribe = emitter.once('twitch:streamOnline').then(handler)
    
    const onlineEvent = {
      id: 'stream123',
      broadcasterId: '456',
      broadcasterUserName: 'streamer',
      broadcasterUserDisplayName: 'Streamer',
      type: 'live' as const,
      startedAt: new Date()
    }
    
    // Emit twice
    await emitter.emit('twitch:streamOnline', onlineEvent)
    await emitter.emit('twitch:streamOnline', onlineEvent)
    
    // Wait for promise to resolve
    await unsubscribe
    
    // Should only be called once
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it('should handle errors in listeners gracefully', async () => {
    const errorHandler = vi.fn(() => {
      throw new Error('Handler error')
    })
    const successHandler = vi.fn()
    
    emitter.on('twitch:message', errorHandler)
    emitter.on('twitch:message', successHandler) 
    
    const messageEvent = {
      id: 'msg123',
      userId: '789',
      userName: 'chatter',
      userDisplayName: 'Chatter',
      message: 'Hello!',
      emotes: [],
      badges: [],
      color: '#FF0000',
      timestamp: Date.now(),
      isFirst: false,
      isReturning: false,
      isSubscriber: false,
      isModerator: false,
      isVip: false
    }
    
    // Emittery does propagate errors by default, so we expect it to throw
    await expect(emitter.emit('twitch:message', messageEvent)).rejects.toThrow('Handler error')
    
    // But the success handler should still have been called before the error
    expect(successHandler).toHaveBeenCalledWith(messageEvent)
    expect(errorHandler).toHaveBeenCalledWith(messageEvent)
  })

  it('should properly type-check event data', () => {
    // This test verifies TypeScript compilation
    // The following should not compile if types are wrong:
    
    emitter.on('twitch:follow', (event) => {
      // TypeScript knows these properties exist
      const userId: string = event.userId
      const userName: string = event.userName
      const followedAt: Date = event.followedAt
      
      expect(userId).toBeDefined()
      expect(userName).toBeDefined()
      expect(followedAt).toBeDefined()
    })
    
    // This would cause a TypeScript error if uncommented:
    // emitter.emit('twitch:follow', { wrongProperty: 'value' })
  })
})
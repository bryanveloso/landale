/**
 * Raw WebSocket event broadcaster for non-tRPC clients (Python analysis, etc.)
 */
import type { ServerWebSocket } from 'bun'
import { eventEmitter } from '@/events'
import { createLogger } from '@landale/logger'
import { nanoid } from 'nanoid'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'event-broadcaster' })

interface WSData {
  req: Request
  correlationId: string
  type: 'trpc' | 'events'
}

interface EventClient {
  id: string
  ws: ServerWebSocket<WSData>
  subscriptions: Set<string>
  correlationId: string
}

interface EventMessage {
  type: 'subscribe' | 'unsubscribe' | 'ping'
  channels?: string[]
  id?: string
}

interface EventBroadcast {
  type: 'event' | 'subscribed' | 'unsubscribed' | 'error' | 'pong' | 'connected'
  channel?: string
  channels?: string[]
  event?: unknown
  timestamp?: number
  error?: string
  id?: string
}

class EventBroadcaster {
  private clients = new Map<string, EventClient>()
  private eventListeners = new Map<string, (data: unknown) => void>()

  constructor() {
    // Set up listeners for Twitch events we want to broadcast
    this.setupEventListeners()
  }

  private setupEventListeners() {
    // Transform twitch:message to chat:message format
    eventEmitter.on('twitch:message', (data) => {
      this.broadcast('chat:message', {
        timestamp: Date.now(),
        username: data.chatterDisplayName || data.chatterName,
        message: data.messageText,
        emotes: this.extractEmotes(data.messageParts),
        is_subscriber: Array.isArray(data.badges) ? data.badges.some((b: { setId: string }) => b.setId === 'subscriber') : false,
        is_moderator: Array.isArray(data.badges) ? data.badges.some((b: { setId: string }) => b.setId === 'moderator') : false
      })
    })

    // Extract emote usage as separate events
    eventEmitter.on('twitch:message', (data) => {
      const emotes = this.extractEmotes(data.messageParts)
      emotes.forEach(emoteName => {
        this.broadcast('chat:emote', {
          timestamp: Date.now(),
          username: data.chatterDisplayName || data.chatterName,
          emote_name: emoteName,
          emote_id: undefined // Emote ID not available in message parts
        })
      })
    })

    // Forward other useful events
    eventEmitter.on('twitch:follow', (data) => {
      this.broadcast('stream:follow', data)
    })

    eventEmitter.on('twitch:subscription', (data) => {
      this.broadcast('stream:subscription', data)
    })

    eventEmitter.on('twitch:cheer', (data) => {
      this.broadcast('stream:cheer', data)
    })
  }

  private extractEmotes(messageParts: Array<{ type: string; text: string }> | undefined): string[] {
    if (!messageParts) return []
    
    return messageParts
      .filter(part => part.type === 'emote')
      .map(part => part.text)
  }

  handleConnection(ws: ServerWebSocket<WSData>, correlationId: string) {
    const client: EventClient = {
      id: nanoid(),
      ws,
      subscriptions: new Set(),
      correlationId
    }

    this.clients.set(client.id, client)
    
    log.info('Event client connected', { 
      metadata: { clientId: client.id, correlationId }
    })

    // Send initial connection confirmation
    this.sendToClient(client, {
      type: 'connected',
      id: client.id,
      timestamp: Date.now()
    })

    return client
  }

  handleMessage(client: EventClient, message: string) {
    try {
      const data = JSON.parse(message) as EventMessage
      
      switch (data.type) {
        case 'subscribe':
          if (data.channels) {
            data.channels.forEach(channel => {
              client.subscriptions.add(channel)
            })
            
            this.sendToClient(client, {
              type: 'subscribed',
              channels: data.channels,
              id: data.id
            })
            
            log.debug('Client subscribed to channels', {
              metadata: { 
                clientId: client.id, 
                channels: data.channels 
              }
            })
          }
          break
          
        case 'unsubscribe':
          if (data.channels) {
            data.channels.forEach(channel => {
              client.subscriptions.delete(channel)
            })
            
            this.sendToClient(client, {
              type: 'unsubscribed',
              channels: data.channels,
              id: data.id
            })
          }
          break
          
        case 'ping':
          this.sendToClient(client, {
            type: 'pong',
            timestamp: Date.now(),
            id: data.id
          })
          break
      }
    } catch (error) {
      log.error('Error handling client message', { 
        error: error as Error,
        metadata: { clientId: client.id }
      })
      
      this.sendToClient(client, {
        type: 'error',
        error: 'Invalid message format'
      })
    }
  }

  handleDisconnect(clientId: string) {
    this.clients.delete(clientId)
    log.info('Event client disconnected', { metadata: { clientId } })
  }

  private sendToClient(client: EventClient, message: EventBroadcast) {
    try {
      client.ws.send(JSON.stringify(message))
    } catch (error) {
      log.error('Failed to send to client', {
        error: error as Error,
        metadata: { clientId: client.id }
      })
    }
  }

  broadcast(channel: string, event: unknown) {
    const message: EventBroadcast = {
      type: 'event',
      channel,
      event,
      timestamp: Date.now()
    }

    for (const client of this.clients.values()) {
      if (client.subscriptions.has(channel)) {
        this.sendToClient(client, message)
      }
    }
  }
}

export const eventBroadcaster = new EventBroadcaster()
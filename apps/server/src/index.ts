import type { Server, ServerWebSocket } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'
import { nanoid } from 'nanoid'

import { env } from '@/lib/env'
import * as Twitch from '@/services/twitch/handlers'
import * as IronMON from '@/services/ironmon'
import * as OBS from '@/services/obs'
import { appRouter } from '@/router'
import { createLogger } from '@landale/logger'
import { displayManager } from '@/services/display-manager'
import { statusBarConfigSchema, statusTextConfigSchema } from '@/types/control'
import { rainwaveService, rainwaveNowPlayingSchema } from '@/services/rainwave'
import { appleMusicService, appleMusicNowPlayingSchema } from '@/services/apple-music'
import { eventEmitter } from '@/events'
import { z } from 'zod'
import { performanceMonitor } from '@/lib/performance'
import { auditLogger, AuditAction, AuditCategory } from '@/lib/audit'
import { eventBroadcaster } from '@/services/event-broadcaster'

import { version } from '../package.json'

// Export types for client packages
export type { AppRouter } from './router'
export * from './services/ironmon/types'
export type { TwitchEvent } from './services/twitch/types'
export type {
  ActivityEvent,
  StatusBarState,
  StatusBarConfig,
  StatusBarMode,
  StatusTextState,
  StatusTextConfig
} from './types/control'
export type { Display } from './services/display-manager'

interface WSData {
  req: Request
  correlationId: string
  type: 'trpc' | 'events'
}

interface ExtendedWebSocket extends ServerWebSocket<WSData> {
  pingInterval?: NodeJS.Timeout
  eventClient?: any
}

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'main' })

console.log(chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`))
log.info('Server starting', { metadata: { environment: env.NODE_ENV, version } })

// Log service startup
void auditLogger.log({
  action: AuditAction.SERVICE_START,
  category: AuditCategory.SERVICE,
  resource: { type: 'service', name: 'landale-server' },
  result: 'success',
  metadata: { version, environment: env.NODE_ENV }
})

const createContext = (opts: CreateBunContextOptions) => {
  // For WebSocket connections, correlation ID is already in the data
  let correlationId: string
  if ('data' in opts && opts.data && typeof opts.data === 'object' && 'correlationId' in opts.data) {
    correlationId = opts.data.correlationId as string
  } else {
    // For HTTP requests, extract from headers
    correlationId = opts.req.headers.get('x-correlation-id') || nanoid()
  }

  const contextLogger = logger.child({ correlationId })

  return {
    req: opts.req,
    correlationId,
    logger: contextLogger
  }
}

const websocket = createBunWSHandler({
  router: appRouter,
  createContext,
  onError: (error: unknown) => {
    log.error('tRPC error occurred', { error: error as Error })
  },
  batching: { enabled: true },
  // Enable WebSocket ping/pong for connection health
  enableSubscriptions: true
})

// Initialize the tRPC server
const server: Server = Bun.serve({
  port: 7175,
  hostname: '0.0.0.0',
  fetch: (request, server) => {
    const url = new URL(request.url)

    // Health check endpoint
    if (url.pathname === '/health') {
      return new Response(
        JSON.stringify({
          status: 'ok',
          timestamp: new Date().toISOString(),
          uptime: process.uptime(),
          version: '0.3.0'
        }),
        {
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Raw event WebSocket endpoint
    if (url.pathname === '/events') {
      const correlationId = request.headers.get('x-correlation-id') || nanoid()
      if (server.upgrade(request, { data: { req: request, correlationId, type: 'events' } })) {
        return
      }
    }
    
    // tRPC WebSocket upgrade
    const correlationId = request.headers.get('x-correlation-id') || nanoid()
    if (server.upgrade(request, { data: { req: request, correlationId, type: 'trpc' } })) {
      return
    }

    return new Response('Please use websocket protocol.', { status: 404 })
  },
  websocket: {
    ...websocket,
    open(ws) {
      const extWs = ws as unknown as ExtendedWebSocket
      const correlationId = extWs.data.correlationId
      const connectionType = extWs.data.type

      log.info('WebSocket connection opened', {
        metadata: {
          remoteAddress: extWs.remoteAddress,
          correlationId,
          type: connectionType
        }
      })

      // Send a ping every 30 seconds to keep connection alive
      const pingInterval = setInterval(() => {
        if (extWs.readyState === 1) {
          // OPEN state
          extWs.ping()
        }
      }, 30000)

      // Store interval ID on the websocket instance
      extWs.pingInterval = pingInterval

      // Route to appropriate handler
      if (connectionType === 'events') {
        // Handle raw event WebSocket
        extWs.eventClient = eventBroadcaster.handleConnection(ws, correlationId)
      } else {
        // Handle tRPC WebSocket
        void websocket.open?.(ws)
      }
    },
    close(ws, code, reason) {
      const extWs = ws as unknown as ExtendedWebSocket
      const correlationId = extWs.data.correlationId

      log.info('WebSocket connection closed', {
        metadata: {
          code,
          reason,
          correlationId
        }
      })

      // Clear the ping interval
      if (extWs.pingInterval) {
        clearInterval(extWs.pingInterval)
        extWs.pingInterval = undefined
      }

      // Handle event client disconnect
      if (extWs.data.type === 'events' && extWs.eventClient) {
        eventBroadcaster.handleDisconnect(extWs.eventClient.id)
      } else {
        void websocket.close?.(ws, code, reason)
      }
    },
    message(ws, message) {
      const extWs = ws as unknown as ExtendedWebSocket
      
      if (extWs.data.type === 'events' && extWs.eventClient) {
        // Handle event WebSocket messages
        eventBroadcaster.handleMessage(extWs.eventClient, message.toString())
      } else {
        // Handle tRPC WebSocket messages
        websocket.message(ws, message)
      }
    }
  }
})

console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('tRPC Server')}: ${server.hostname ?? 'localhost'}:${server.port?.toString() ?? '7175'}`
)
console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('Event Stream')}: ${server.hostname ?? 'localhost'}:${server.port?.toString() ?? '7175'}/events`
)

// Register displays
displayManager.register('statusBar', statusBarConfigSchema, {
  mode: 'preshow',
  text: undefined,
  isVisible: true,
  position: 'bottom'
})

displayManager.register('statusText', statusTextConfigSchema, {
  text: '',
  isVisible: true,
  position: 'bottom',
  fontSize: 'medium',
  animation: 'fade'
})

// Example: Follower counter
displayManager.register(
  'followerCount',
  z.object({
    current: z.number(),
    goal: z.number(),
    label: z.string()
  }),
  {
    current: 0,
    goal: 100,
    label: 'Follower Goal'
  }
)

// Rainwave now playing
displayManager.register(
  'rainwave',
  rainwaveNowPlayingSchema,
  {
    stationId: 3, // Covers station by default
    isEnabled: false,
    apiKey: env.RAINWAVE_API_KEY || '',
    userId: env.RAINWAVE_USER_ID || ''
  },
  {
    displayName: 'Rainwave Now Playing',
    category: 'music'
  }
)

// Apple Music now playing
displayManager.register(
  'appleMusic',
  appleMusicNowPlayingSchema,
  {
    isEnabled: true,
    isAuthorized: true
  },
  {
    displayName: 'Apple Music Now Playing',
    category: 'music'
  }
)

log.info('Registered display services', {
  metadata: { displays: ['statusBar', 'statusText', 'followerCount', 'rainwave', 'appleMusic'] }
})

// Handle display updates for Rainwave
eventEmitter.on('display:rainwave:update', (display: unknown) => {
  rainwaveService.updateConfig((display as { data: Parameters<typeof rainwaveService.updateConfig>[0] }).data)
})

// Handle display updates for Apple Music
eventEmitter.on('display:appleMusic:update', (display: unknown) => {
  appleMusicService.updateConfig((display as { data: Parameters<typeof appleMusicService.updateConfig>[0] }).data)
})

// Initialize IronMON TCP Server
try {
  IronMON.initialize()
  log.info('IronMON TCP Server initialized successfully')
} catch (error) {
  log.error('Failed to initialize IronMON TCP Server', { error: error as Error })
}

// Initialize Twitch EventSub
void Twitch.initialize()
  .then(() => {
    log.info('Twitch EventSub initialized successfully')
  })
  .catch((error: unknown) => {
    log.error('Failed to initialize Twitch EventSub integration', { error: error as Error })
  })

// Initialize OBS WebSocket
void OBS.initialize()
  .then(() => {
    log.info('OBS WebSocket initialized successfully')
  })
  .catch((error: unknown) => {
    log.error('Failed to initialize OBS WebSocket integration', { error: error as Error })
  })

// Initialize Rainwave service
try {
  rainwaveService.init()
  log.info('Rainwave service initialized successfully')
} catch (error) {
  log.error('Failed to initialize Rainwave service', { error: error as Error })
}

// Initialize Apple Music service (host-based)
try {
  appleMusicService.init()
  log.info('Apple Music service initialized successfully')
} catch (error) {
  log.error('Failed to initialize Apple Music service', { error: error as Error })
}

// Handle graceful shutdown
const shutdown = async (signal: string) => {
  log.info('Shutting down server', { metadata: { signal } })

  // Log service shutdown
  await auditLogger.log({
    action: AuditAction.SERVICE_STOP,
    category: AuditCategory.SERVICE,
    resource: { type: 'service', name: 'landale-server' },
    result: 'success',
    metadata: { signal }
  })

  // Notify all connected clients to reconnect
  log.info('Broadcasting reconnection notification to all clients')

  // Stop accepting new connections
  void server.stop()

  // Cleanup other services
  IronMON.shutdown()
  OBS.shutdown()

  // Shutdown monitoring services
  performanceMonitor.shutdown()
  await auditLogger.shutdown()

  process.exit(0)
}

process.on('SIGINT', () => {
  void shutdown('SIGINT')
})
process.on('SIGTERM', () => {
  void shutdown('SIGTERM')
})

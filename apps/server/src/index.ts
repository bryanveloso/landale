import type { Server, ServerWebSocket } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'
import { nanoid } from 'nanoid'

import { env } from '@/lib/env'
import * as Twitch from '@/services/twitch/handlers'
import * as IronMON from '@/services/ironmon'
import * as OBS from '@/services/obs'
import { appRouter } from '@/router'
import { createLogger } from '@/lib/logger'
import { displayManager } from '@/services/display-manager'
import { statusBarConfigSchema, statusTextConfigSchema } from '@/types/control'
import { rainwaveService, rainwaveNowPlayingSchema } from '@/services/rainwave'
import { appleMusicService, appleMusicNowPlayingSchema } from '@/services/apple-music'
import { eventEmitter } from '@/events'
import { z } from 'zod'
import { performanceMonitor } from '@/lib/performance'
import { auditLogger, AuditAction, AuditCategory } from '@/lib/audit'
import { eventBroadcaster } from '@/services/event-broadcaster'
import { SERVICE_CONFIG } from '@landale/service-config'
import { getHealthMonitor } from '@/lib/health'
import { pm2Manager } from '@/services/pm2'

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
export type { ProcessInfo } from './services/pm2'

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

// Type guard to check if websocket has our extended properties
function isExtendedWebSocket(ws: any): ws is ServerWebSocket<WSData> & {
  pingInterval?: NodeJS.Timeout
  eventClient?: EventClient
} {
  return 'data' in ws && ws.data !== undefined && 'correlationId' in ws.data && 'type' in ws.data
}

// Helper to safely get extended websocket properties
function getExtendedProps(ws: any) {
  const props = {
    pingInterval: undefined as NodeJS.Timeout | undefined,
    eventClient: undefined as EventClient | undefined
  }
  
  // Use object property access to avoid type issues
  if ('pingInterval' in ws) {
    props.pingInterval = ws.pingInterval
  }
  if ('eventClient' in ws) {
    props.eventClient = ws.eventClient
  }
  
  return props
}

// Helper to safely set extended websocket properties
function setExtendedProps(ws: any, props: { pingInterval?: NodeJS.Timeout; eventClient?: EventClient }) {
  if (props.pingInterval !== undefined) {
    ws.pingInterval = props.pingInterval
  }
  if (props.eventClient !== undefined) {
    ws.eventClient = props.eventClient
  }
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

// Get server configuration
const serverConfig = SERVICE_CONFIG.server
const serverPort = serverConfig.ports.http || 7175

// Initialize the tRPC server
const server: Server = Bun.serve({
  port: serverPort,
  hostname: '0.0.0.0',
  fetch: async (request, server) => {
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

    // Companion HTTP endpoints for Stream Deck
    if (url.pathname.startsWith('/api/companion/process/')) {
      const parts = url.pathname.split('/')
      const machine = parts[4]
      const processName = parts[5]
      const action = parts[6]

      if (request.method === 'GET' && action === 'status' && machine && processName) {
        const { getProcessStatus } = await import('@/router/companion')
        const status = await getProcessStatus(machine, processName)
        return Response.json(status)
      }

      if (request.method === 'POST' && machine && processName) {
        const { startProcess, stopProcess, restartProcess } = await import('@/router/companion')
        
        switch (action) {
          case 'start':
            return Response.json(await startProcess(machine, processName))
          case 'stop':
            return Response.json(await stopProcess(machine, processName))
          case 'restart':
            return Response.json(await restartProcess(machine, processName))
        }
      }

      if (request.method === 'GET' && processName === 'list' && machine) {
        const { listProcesses } = await import('@/router/companion')
        return Response.json(await listProcesses(machine))
      }
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
      if (!isExtendedWebSocket(ws)) {
        log.error('Invalid WebSocket connection - missing data')
        return
      }
      
      const correlationId = ws.data.correlationId
      const connectionType = ws.data.type

      log.info('WebSocket connection opened', {
        metadata: {
          remoteAddress: ws.remoteAddress,
          correlationId,
          type: connectionType
        }
      })

      // Send a ping every 30 seconds to keep connection alive
      const pingInterval = setInterval(() => {
        if (ws.readyState === 1) {
          // OPEN state
          ws.ping()
        }
      }, 30000)

      // Store interval ID on the websocket instance
      setExtendedProps(ws, { pingInterval })

      // Route to appropriate handler
      if (connectionType === 'events') {
        // Handle raw event WebSocket
        const eventClient = eventBroadcaster.handleConnection(ws, correlationId)
        setExtendedProps(ws, { eventClient })
      } else {
        // Handle tRPC WebSocket
        void websocket.open?.(ws)
      }
    },
    close(ws, code, reason) {
      if (!isExtendedWebSocket(ws)) {
        log.error('Invalid WebSocket connection - missing data')
        return
      }
      
      const correlationId = ws.data.correlationId
      const props = getExtendedProps(ws)

      log.info('WebSocket connection closed', {
        metadata: {
          code,
          reason,
          correlationId
        }
      })

      // Clear the ping interval
      if (props.pingInterval) {
        clearInterval(props.pingInterval)
        setExtendedProps(ws, { pingInterval: undefined })
      }

      // Handle event client disconnect
      if (ws.data.type === 'events' && props.eventClient) {
        eventBroadcaster.handleDisconnect(props.eventClient.id)
      } else {
        void websocket.close?.(ws, code, reason)
      }
    },
    message(ws, message) {
      if (!isExtendedWebSocket(ws)) {
        log.error('Invalid WebSocket connection - missing data')
        return
      }
      
      const props = getExtendedProps(ws)
      
      if (ws.data.type === 'events' && props.eventClient) {
        // Handle event WebSocket messages
        eventBroadcaster.handleMessage(props.eventClient, message.toString())
      } else {
        // Handle tRPC WebSocket messages
        void websocket.message(ws, message)
      }
    }
  }
})

const displayHost = serverConfig.host || 'localhost'
console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('tRPC Server')}: ${displayHost}:${server.port?.toString() ?? '7175'}`
)
console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('Event Stream')}: ${displayHost}:${server.port?.toString() ?? '7175'}/events`
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

// Initialize PM2 Manager
void pm2Manager.connect('localhost')
  .then(() => {
    log.info('PM2 Manager initialized successfully')
  })
  .catch((error: unknown) => {
    log.error('Failed to initialize PM2 Manager', { error: error as Error })
  })

// Initialize health monitoring
const healthMonitor = getHealthMonitor()
healthMonitor.setEventBroadcaster(eventBroadcaster)

// Register services for health monitoring
healthMonitor.registerService('database')
healthMonitor.registerService('obs')
healthMonitor.registerService('rainwave')
healthMonitor.registerService('apple-music')
healthMonitor.registerService('twitch')
healthMonitor.registerService('ironmon')

// Start health monitoring
healthMonitor.start()
log.info('Health monitoring started')

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
  healthMonitor.stop()
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

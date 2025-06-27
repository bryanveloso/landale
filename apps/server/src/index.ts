import type { Server, ServerWebSocket } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'

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
}

interface ExtendedWebSocket extends ServerWebSocket<WSData> {
  pingInterval?: NodeJS.Timeout
}

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'main' })

console.log(chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`))
log.info('Server starting', { environment: env.NODE_ENV, version })

const createContext = async (opts: CreateBunContextOptions) => {
  return {
    req: opts.req
  }
}

const websocket = createBunWSHandler({
  router: appRouter,
  createContext,
  onError: (error: unknown) => {
    log.error('tRPC error occurred', { error })
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

    // WebSocket upgrade
    if (server.upgrade(request, { data: { req: request } })) {
      return
    }

    return new Response('Please use websocket protocol.', { status: 404 })
  },
  websocket: {
    ...websocket,
    open(ws) {
      const extWs = ws as unknown as ExtendedWebSocket
      log.info('WebSocket connection opened', { remoteAddress: extWs.remoteAddress })
      // Send a ping every 30 seconds to keep connection alive
      const pingInterval = setInterval(() => {
        if (extWs.readyState === 1) {
          // OPEN state
          extWs.ping()
        }
      }, 30000)

      // Store interval ID on the websocket instance
      extWs.pingInterval = pingInterval

      websocket.open?.(ws)
    },
    close(ws, code, reason) {
      const extWs = ws as unknown as ExtendedWebSocket
      log.info('WebSocket connection closed', { code, reason })
      // Clear the ping interval
      if (extWs.pingInterval) {
        clearInterval(extWs.pingInterval)
        extWs.pingInterval = undefined
      }

      websocket.close?.(ws, code, reason)
    },
    message: websocket.message
  }
})

console.log(`  ${chalk.green('➜')}  ${chalk.bold('tRPC Server')}: ${server.hostname}:${server.port}`)

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
  displays: ['statusBar', 'statusText', 'followerCount', 'rainwave', 'appleMusic']
})

// Handle display updates for Rainwave
eventEmitter.on('display:rainwave:update', (display) => {
  rainwaveService.updateConfig(display.data)
})

// Handle display updates for Apple Music
eventEmitter.on('display:appleMusic:update', (display) => {
  appleMusicService.updateConfig(display.data)
})

// Initialize IronMON TCP Server
IronMON.initialize()
  .then(() => {
    log.info('IronMON TCP Server initialized successfully')
  })
  .catch((error) => {
    log.error('Failed to initialize IronMON TCP Server', { error })
  })

// Initialize Twitch EventSub
Twitch.initialize()
  .then(() => {
    log.info('Twitch EventSub initialized successfully')
  })
  .catch((error) => {
    log.error('Failed to initialize Twitch EventSub integration', { error })
  })

// Initialize OBS WebSocket
OBS.initialize()
  .then(() => {
    log.info('OBS WebSocket initialized successfully')
  })
  .catch((error) => {
    log.error('Failed to initialize OBS WebSocket integration', { error })
  })

// Initialize Rainwave service
rainwaveService
  .init()
  .then(() => {
    log.info('Rainwave service initialized successfully')
  })
  .catch((error) => {
    log.error('Failed to initialize Rainwave service', { error })
  })

// Initialize Apple Music service (host-based)
appleMusicService
  .init()
  .then(() => {
    log.info('Apple Music service initialized successfully')
  })
  .catch((error) => {
    log.error('Failed to initialize Apple Music service', { error })
  })

// Handle graceful shutdown
const shutdown = async (signal: string) => {
  log.info('Shutting down server', { signal })

  // Notify all connected clients to reconnect
  log.info('Broadcasting reconnection notification to all clients')

  // Stop accepting new connections
  server.stop()

  // Cleanup other services
  await IronMON.shutdown()
  await OBS.shutdown()

  process.exit(0)
}

process.on('SIGINT', () => shutdown('SIGINT'))
process.on('SIGTERM', () => shutdown('SIGTERM'))

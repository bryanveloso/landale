import type { Server } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'

import { env } from '@/lib/env'
import * as Twitch from '@/events/twitch/handlers'
import * as IronMON from '@/events/ironmon'
import { appRouter, type AppRouter } from '@/trpc'
import { createLogger } from '@/lib/logger'

import { version } from '../package.json'

const log = createLogger('main')

console.log(chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`))
log.info(`Environment: ${env.NODE_ENV}`)

const createContext = async (_opts: CreateBunContextOptions) => {
  return {}
}

const websocket = createBunWSHandler({
  router: appRouter,
  createContext,
  onError: (error: unknown) => {
    log.error('tRPC error occurred', error)
  },
  batching: { enabled: true }
})

// Initialize the tRPC server
const server: Server = Bun.serve({
  port: 7175,
  hostname: '0.0.0.0',
  fetch: (request, server) => {
    const url = new URL(request.url)
    
    // Health check endpoint
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: '0.3.0'
      }), {
        headers: { 'Content-Type': 'application/json' }
      })
    }
    
    // WebSocket upgrade
    if (server.upgrade(request, { data: { req: request } })) {
      return
    }

    return new Response('Please use websocket protocol', { status: 404 })
  },
  websocket
})

console.log(`  ${chalk.green('➜')}  ${chalk.bold('tRPC Server')}: ${server.hostname}:${server.port}`)

// Initialize IronMON TCP Server
IronMON.initialize()
  .then(() => {
    log.info('IronMON TCP Server initialized successfully.')
  })
  .catch((error) => {
    log.error('Failed to initialize IronMON TCP Server:', error)
  })

// Initialize Twitch EventSub
Twitch.initialize()
  .then(() => {
    log.info('Twitch EventSub initialized successfully.')
  })
  .catch((error) => {
    log.error('Failed to initialize Twitch EventSub integration:', error)
  })

// Handle graceful shutdown
process.on('SIGINT', async () => {
  console.log(`\n  🛑 Shutting down server...`)
  server.stop()
  await IronMON.shutdown()
  process.exit(0)
})

// Export AppRouter type for client consumption
export type { AppRouter }

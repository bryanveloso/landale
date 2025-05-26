import type { Server } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'

import * as Twitch from '@/events/twitch/handlers'
import * as IronMON from '@/events/ironmon'
import { appRouter, type AppRouter } from '@/trpc'

import { version } from '../package.json'

console.log(chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`))

const createContext = async (_opts: CreateBunContextOptions) => {
  return {}
}

const websocket = createBunWSHandler({
  router: appRouter,
  createContext,
  onError: console.error,
  batching: { enabled: true }
})

// Initialize the tRPC server
const server: Server = Bun.serve({
  port: 7175,
  hostname: '0.0.0.0',
  fetch: (request, server) => {
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
    console.log(`  ${chalk.green('•')}  IronMON TCP Server initialized successfully.`)
  })
  .catch((error) => {
    console.error(`  ${chalk.red('•')}  Failed to initialize IronMON TCP Server:`, error)
  })

// Initialize Twitch EventSub
Twitch.initialize()
  .then(() => {
    console.log(`  ${chalk.green('•')}  Twitch EventSub initialized successfully.`)
  })
  .catch((error) => {
    console.error(`  ${chalk.red('•')}  Failed to initialize Twitch EventSub integration:`, error)
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

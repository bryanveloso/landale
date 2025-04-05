import type { Server } from 'bun'
import chalk from 'chalk'
import { createBunWSHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'

import * as Twitch from '@/events/twitch/handlers'
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

// const server: Server = Bun.serve(
//   createBunServeHandler(
//     {
//       router: appRouter,
//       createContext,
//       endpoint: '/trpc',
//       onError: (error: Error) => {
//         console.error('tRPC error:', error)
//       },
//       batching: { enabled: true }
//     } as TrpcHandlerOptions,
//     {
//       port: 7175,
//       hostname: '0.0.0.0',
//       fetch(_request, _server) {
//         return new Response('Not found', { status: 404 })
//       }
//     } as ServeOptions
//   )
// )

console.log(`  ${chalk.green('➜')}  ${chalk.bold('tRPC Server')}: ${server.hostname}:${server.port}`)

// Initialize Twitch EventSub
Twitch.initialize()
  .then(() => {
    console.log(`  ${chalk.green('•')}  Twitch EventSub initialized successfully.`)
  })
  .catch((error) => {
    console.error(`  ${chalk.red('•')}  Failed to initialize Twitch EventSub integration:`, error)
  })

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log(`\n  🛑 Shutting down server...`)
  server.stop()
  process.exit(0)
})

// Export AppRouter type for client consumption
export type { AppRouter }

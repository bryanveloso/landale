import type { ServeOptions, Server } from 'bun'
import chalk from 'chalk'
import { createBunServeHandler, type CreateBunContextOptions } from 'trpc-bun-adapter'

import * as Twitch from '@/events/twitch/handlers'
import { appRouter } from '@/trpc'

import { version } from '../package.json'

console.log(chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`))

const createContext = async (opts: CreateBunContextOptions) => {
  return {}
}

interface TrpcHandlerOptions {
  router: typeof appRouter
  createContext: (opts: CreateBunContextOptions) => Promise<Record<string, never>>
  endpoint: string
  onError: (error: Error) => void
  batching: { enabled: boolean }
}

const server: Server = Bun.serve(
  createBunServeHandler(
    {
      router: appRouter,
      createContext,
      endpoint: '/trpc',
      onError: (error: Error) => {
        console.error('tRPC error:', error)
      },
      batching: { enabled: true }
    } as TrpcHandlerOptions,
    {
      port: 7175,
      hostname: '0.0.0.0',
      fetch(request, server) {
        return new Response('Not found', { status: 404 })
      }
    } as ServeOptions
  )
)

console.log(`  ${chalk.green('➜')}  ${chalk.bold('tRCP Server')}: ${server.hostname}:${server.port}`)

Twitch.initialize()
  .then(() => {
    console.log(`  ${chalk.green('•')}  Twitch EventSub initialized successfully.`)
  })
  .catch((error) => {
    console.error(`  ${chalk.red('•')}  Failed to initialize Twitch EventSub integration:`, error)
  })

process.on('SIGINT', () => {
  console.log(`\n  🛑 Shutting down server...`)
  server.stop()
  process.exit(0)
})

export type { AppRouter } from '@/trpc'

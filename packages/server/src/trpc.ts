import { initTRPC } from '@trpc/server'
import { eventEmitter } from './events'

// Initialize tRPC.
const t = initTRPC.create()
const router = t.router
const publicProcedure = t.procedure

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* () {
    const stream = eventEmitter.events('twitch:message')
    try {
      for await (const data of stream) {
        yield data
      }
    } finally {
      // Cleanup happens automatically when the client unsubscribes.
    }
  })
})

export const ironmonRouter = router({
  onInit: publicProcedure.subscription(async function* () {
    const stream = eventEmitter.events('ironmon:init')
    try {
      for await (const data of stream) {
        yield data
      }
    } finally {
      // Cleanup happens automatically when the client unsubscribes.
    }
  }),
  
  onSeed: publicProcedure.subscription(async function* () {
    const stream = eventEmitter.events('ironmon:seed')
    try {
      for await (const data of stream) {
        yield data
      }
    } finally {
      // Cleanup happens automatically when the client unsubscribes.
    }
  }),
  
  onCheckpoint: publicProcedure.subscription(async function* () {
    const stream = eventEmitter.events('ironmon:checkpoint')
    try {
      for await (const data of stream) {
        yield data
      }
    } finally {
      // Cleanup happens automatically when the client unsubscribes.
    }
  }),
  
  // Combined subscription for all IronMON events
  onMessage: publicProcedure.subscription(async function* () {
    // Create a unified stream by listening to all events
    const unsubscribers: (() => void)[] = []
    const queue: any[] = []
    let resolveNext: ((value: IteratorResult<any>) => void) | null = null
    
    // Subscribe to all IronMON events
    const eventTypes = ['ironmon:init', 'ironmon:seed', 'ironmon:checkpoint'] as const
    
    for (const eventType of eventTypes) {
      const unsubscribe = eventEmitter.on(eventType, (data) => {
        if (resolveNext) {
          resolveNext({ value: data, done: false })
          resolveNext = null
        } else {
          queue.push(data)
        }
      })
      unsubscribers.push(unsubscribe)
    }
    
    try {
      while (true) {
        if (queue.length > 0) {
          yield queue.shift()
        } else {
          // Wait for next event
          yield await new Promise<any>((resolve) => {
            resolveNext = (result) => resolve(result.value)
          })
        }
      }
    } finally {
      // Cleanup all subscriptions
      unsubscribers.forEach(fn => fn())
    }
  })
})

export const appRouter = router({
  twitch: twitchRouter,
  ironmon: ironmonRouter
})

// Define the router type
export type AppRouter = typeof appRouter

import { z } from 'zod'
import { t, publicProcedure, type Router } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { pm2Manager, type ProcessInfo } from '@/services/pm2'
import { observable } from '@trpc/server/observable'
import { EventEmitter } from 'events'

// Process status emitter for subscriptions
const processEvents = new EventEmitter()

// Poll PM2 for status changes
let pollInterval: NodeJS.Timeout | null = null
const startPolling = () => {
  if (pollInterval) return
  
  pollInterval = setInterval(() => {
    void (async () => {
      try {
        const processes = await pm2Manager.list('localhost')
        processEvents.emit('status', processes)
      } catch {
        // Silent fail - will retry next interval
      }
    })()
  }, 5000) // Poll every 5 seconds
}

// Start polling when server starts
startPolling()

export const processesRouter = t.router({
  // List all processes on a machine
  list: publicProcedure
    .input(z.object({ 
      machine: z.string().default('localhost') 
    }))
    .query(async ({ input }) => {
      try {
        return await pm2Manager.list(input.machine)
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to list processes'
        })
      }
    }),

  // Start a process
  start: publicProcedure
    .input(z.object({
      machine: z.string(),
      process: z.string()
    }))
    .mutation(async ({ input }) => {
      try {
        await pm2Manager.start(input.machine, input.process)
        return { success: true }
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to start process'
        })
      }
    }),

  // Stop a process
  stop: publicProcedure
    .input(z.object({
      machine: z.string(),
      process: z.string()
    }))
    .mutation(async ({ input }) => {
      try {
        await pm2Manager.stop(input.machine, input.process)
        return { success: true }
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to stop process'
        })
      }
    }),

  // Restart a process
  restart: publicProcedure
    .input(z.object({
      machine: z.string(),
      process: z.string()
    }))
    .mutation(async ({ input }) => {
      try {
        await pm2Manager.restart(input.machine, input.process)
        return { success: true }
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to restart process'
        })
      }
    }),

  // Get detailed info about a process
  describe: publicProcedure
    .input(z.object({
      machine: z.string(),
      process: z.string()
    }))
    .query(async ({ input }) => {
      try {
        const result = await pm2Manager.describe(input.machine, input.process)
        return result as unknown as Record<string, unknown>
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to describe process'
        })
      }
    }),

  // Flush logs
  flush: publicProcedure
    .input(z.object({
      machine: z.string(),
      process: z.string().optional()
    }))
    .mutation(async ({ input }) => {
      try {
        await pm2Manager.flush(input.machine, input.process)
        return { success: true }
      } catch (error) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Failed to flush logs'
        })
      }
    }),

  // Subscribe to process status updates
  onStatusUpdate: publicProcedure
    .input(z.object({
      machine: z.string().default('localhost')
    }))
    .subscription(({ input }) => {
      return observable<ProcessInfo[]>((emit) => {
        // Send initial state
        void (async () => {
          try {
            const processes = await pm2Manager.list(input.machine)
            emit.next(processes)
          } catch (error) {
            console.error('Failed to get initial process list:', error)
            emit.next([])
          }
        })()

        // Set up event listener for updates
        const handleUpdate = (processes: ProcessInfo[]) => {
          // Emit updates for all machines, the client will filter
          emit.next(processes)
        }
        
        processEvents.on('status', handleUpdate)
        
        // For non-localhost machines, we need to poll since we don't have remote events
        let pollInterval: NodeJS.Timeout | null = null
        if (input.machine !== 'localhost') {
          pollInterval = setInterval(async () => {
            try {
              const processes = await pm2Manager.list(input.machine)
              emit.next(processes)
            } catch (error) {
              console.error(`Failed to poll ${input.machine}:`, error)
            }
          }, 5000) // Poll every 5 seconds
        }
        
        // Cleanup function
        return () => {
          processEvents.off('status', handleUpdate)
          if (pollInterval) {
            clearInterval(pollInterval)
          }
        }
      })
    })
})

// Cleanup on exit
process.on('SIGINT', () => {
  if (pollInterval) {
    clearInterval(pollInterval)
  }
})

process.on('SIGTERM', () => {
  if (pollInterval) {
    clearInterval(pollInterval)
  }
})
import { z } from 'zod'
import { t, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { pm2Manager, type ProcessInfo } from '@/services/pm2'
import { observable } from '@trpc/server/observable'
import { EventEmitter } from 'events'

// Process status emitter for subscriptions
const processEvents = new EventEmitter()


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
            console.log(`[PM2] Getting initial process list for ${input.machine}...`)
            const processes = await pm2Manager.list(input.machine)
            console.log(`[PM2] Initial fetch got ${processes.length} processes from ${input.machine}:`, processes.map(p => p.name))
            emit.next(processes)
          } catch (error) {
            console.error(`[PM2] Failed to get initial process list for ${input.machine}:`, error)
            // Use same pattern as the log variable at top of file
            throw new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to get initial process list'
            })
          }
        })()

        // Set up event listener for updates - only for localhost
        const handleUpdate = (processes: ProcessInfo[]) => {
          // Only emit localhost updates to localhost subscribers
          if (input.machine === 'localhost') {
            emit.next(processes)
          }
        }
        
        processEvents.on('status', handleUpdate)
        
        // For non-localhost machines, we need to poll since we don't have remote events
        let pollInterval: NodeJS.Timeout | null = null
        if (input.machine !== 'localhost') {
          console.log(`[PM2] Starting polling for machine: ${input.machine}`)
          pollInterval = setInterval(async () => {
            try {
              console.log(`[PM2] Polling ${input.machine} for processes...`)
              const processes = await pm2Manager.list(input.machine)
              console.log(`[PM2] Got ${processes.length} processes from ${input.machine}:`, processes.map(p => p.name))
              emit.next(processes)
            } catch (error) {
              console.error(`[PM2] Failed to poll ${input.machine}:`, error)
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


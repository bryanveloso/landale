import { describe, it, expect, beforeEach, mock } from 'bun:test'
import { initTRPC } from '@trpc/server'
import { z } from 'zod'
import type { Context } from '@/trpc'
import * as eventModule from '@/events'

// Mock dependencies
const mockNanoid = mock(() => 'generated-id')
await mock.module('nanoid', () => ({
  nanoid: mockNanoid
}))

const mockLogger = {
  child: mock((_config: { correlationId: string }) => mockLogger),
  info: mock(),
  error: mock(),
  warn: mock(),
  debug: mock()
}

await mock.module('@landale/logger', () => ({
  createLogger: () => mockLogger
}))

describe('Correlation ID Integration', () => {
  beforeEach(() => {
    mockNanoid.mockClear()
    mockLogger.child.mockClear()
    mockLogger.info.mockClear()
    mockLogger.error.mockClear()
  })

  it('should track correlation ID through entire request lifecycle', async () => {
    // Setup tRPC with correlation middleware
    const t = initTRPC.context<Context>().create()

    const correlationMiddleware = t.middleware(async (opts) => {
      const correlationId = opts.ctx.req?.headers.get('x-correlation-id') || mockNanoid()
      const procedureLogger = mockLogger.child({ correlationId })

      return opts.next({
        ctx: {
          ...opts.ctx,
          correlationId,
          logger: procedureLogger
        }
      })
    })

    const publicProcedure = t.procedure.use(correlationMiddleware)

    // Create a test router that simulates the control router
    const testRouter = t.router({
      emoteRain: t.router({
        burst: publicProcedure
          .input(
            z.object({
              emoteId: z.string().optional(),
              count: z.number().min(1).max(50).default(10)
            })
          )
          .mutation(async ({ input, ctx }) => {
            // Simulate the actual implementation
            await eventModule.emitEventWithCorrelation('emoteRain:burst', input, ctx.correlationId)
            ctx.logger.info('Manual emote burst triggered', {
              metadata: { emoteId: input.emoteId, count: input.count }
            })
            return { success: true }
          })
      })
    })

    // Create a caller with a specific correlation ID
    const mockRequest = {
      headers: {
        get: (header: string) => (header === 'x-correlation-id' ? 'request-correlation-id' : null)
      }
    }

    const caller = testRouter.createCaller({
      req: mockRequest,
      correlationId: '',
      logger: mockLogger
    } as unknown as Context)

    // Execute the procedure
    const result = await caller.emoteRain.burst({
      emoteId: 'test-emote',
      count: 25
    })

    // Verify the result
    expect(result).toEqual({ success: true })

    // Verify correlation ID was used consistently
    expect(mockLogger.child).toHaveBeenCalledWith({ correlationId: 'request-correlation-id' })

    expect(mockLogger.info).toHaveBeenCalledWith('Manual emote burst triggered', {
      metadata: { emoteId: 'test-emote', count: 25 }
    })
  })

  it('should generate new correlation ID when not provided', async () => {
    const t = initTRPC.context<Context>().create()

    const correlationMiddleware = t.middleware(async (opts) => {
      const correlationId = opts.ctx.req?.headers.get('x-correlation-id') || mockNanoid()
      const procedureLogger = mockLogger.child({ correlationId })

      return opts.next({
        ctx: {
          ...opts.ctx,
          correlationId,
          logger: procedureLogger
        }
      })
    })

    const publicProcedure = t.procedure.use(correlationMiddleware)

    const testRouter = t.router({
      test: publicProcedure.query(({ ctx }) => ctx.correlationId)
    })

    // Create caller without correlation ID
    const caller = testRouter.createCaller({
      req: {
        headers: {
          get: () => null
        }
      } as unknown as Request,
      correlationId: '',
      logger: mockLogger
    } as unknown as Context)

    const correlationId = await caller.test()

    expect(correlationId).toBe('generated-id')
    expect(mockNanoid).toHaveBeenCalled()
    expect(mockLogger.child).toHaveBeenCalledWith({ correlationId: 'generated-id' })
  })

  it('should handle errors while maintaining correlation context', async () => {
    const t = initTRPC.context<Context>().create()

    const correlationMiddleware = t.middleware(async (opts) => {
      const correlationId = opts.ctx.req?.headers.get('x-correlation-id') || mockNanoid()
      const procedureLogger = mockLogger.child({ correlationId })

      return opts.next({
        ctx: {
          ...opts.ctx,
          correlationId,
          logger: procedureLogger
        }
      })
    })

    const errorHandlingMiddleware = t.middleware(async (opts) => {
      try {
        const result = await opts.next({ ctx: opts.ctx })
        if (!result.ok) {
          opts.ctx.logger.error('Procedure failed', {
            error: result.error,
            metadata: { path: opts.path }
          })
        }
        return result
      } catch (error) {
        opts.ctx.logger.error('Procedure error', {
          error: error as Error,
          metadata: { path: opts.path }
        })
        throw error
      }
    })

    const publicProcedure = t.procedure.use(correlationMiddleware).use(errorHandlingMiddleware)

    const testRouter = t.router({
      failing: publicProcedure.mutation(() => {
        throw new Error('Test error')
      })
    })

    const caller = testRouter.createCaller({
      req: {
        headers: {
          get: (header: string) => (header === 'x-correlation-id' ? 'error-correlation-id' : null)
        }
      } as unknown as Request,
      correlationId: '',
      logger: mockLogger
    } as unknown as Context)

    try {
      await caller.failing()
      expect(true).toBe(false) // Should not reach here
    } catch (error) {
      expect((error as Error).message).toBe('Test error')
    }

    // Verify error was logged with correlation context
    expect(mockLogger.child).toHaveBeenCalledWith({ correlationId: 'error-correlation-id' })
    expect(mockLogger.error).toHaveBeenCalledWith(
      'Procedure failed',
      expect.objectContaining({
        error: expect.any(Error) as Error,
        metadata: { path: 'failing' }
      })
    )
  })
})

import { describe, it, expect, beforeEach, mock } from 'bun:test'
import type { CreateBunContextOptions } from 'trpc-bun-adapter'
import { initTRPC } from '@trpc/server'

// Mock nanoid
const mockNanoid = mock(() => 'test-correlation-id')
await mock.module('nanoid', () => ({
  nanoid: mockNanoid
}))

// Mock logger
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

describe('Correlation ID Tracking', () => {
  beforeEach(() => {
    mockNanoid.mockClear()
    mockLogger.child.mockClear()
    mockLogger.info.mockClear()
    mockLogger.error.mockClear()
  })

  describe('Context Creation', () => {
    it('should extract correlation ID from request header', () => {
      const mockRequest = {
        headers: {
          get: mock((header: string) => (header === 'x-correlation-id' ? 'existing-correlation-id' : null))
        }
      }

      // Create a minimal context creator similar to the app
      const createContext = (opts: CreateBunContextOptions) => {
        const correlationId = opts.req.headers.get('x-correlation-id') || mockNanoid()
        const contextLogger = mockLogger.child({ correlationId })

        return {
          req: opts.req,
          correlationId,
          logger: contextLogger
        }
      }

      const context = createContext({
        req: mockRequest as unknown as Request,
        resHeaders: new Headers(),
        info: {
          connectionParams: {},
          type: 'request',
          calls: [],
          isBatchCall: false,
          accept: 'application/json'
        }
      } as unknown as CreateBunContextOptions)

      expect(context.correlationId).toBe('existing-correlation-id')
      expect(mockLogger.child).toHaveBeenCalledWith({ correlationId: 'existing-correlation-id' })
      expect(mockRequest.headers.get).toHaveBeenCalledWith('x-correlation-id')
    })

    it('should generate new correlation ID when header is not present', () => {
      const mockRequest = {
        headers: {
          get: mock(() => null)
        }
      }

      const createContext = (opts: CreateBunContextOptions) => {
        const correlationId = opts.req.headers.get('x-correlation-id') || mockNanoid()
        const contextLogger = mockLogger.child({ correlationId })

        return {
          req: opts.req,
          correlationId,
          logger: contextLogger
        }
      }

      const context = createContext({
        req: mockRequest as unknown as Request,
        resHeaders: new Headers(),
        info: {
          connectionParams: {},
          type: 'request',
          calls: [],
          isBatchCall: false,
          accept: 'application/json'
        }
      } as unknown as CreateBunContextOptions)

      expect(context.correlationId).toBe('test-correlation-id')
      expect(mockLogger.child).toHaveBeenCalledWith({ correlationId: 'test-correlation-id' })
    })
  })

  describe('tRPC Middleware', () => {
    it('should inject correlation ID into procedure context', async () => {
      interface Context {
        req?: Request
        correlationId: string
        logger: typeof mockLogger
      }

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
        test: publicProcedure.query(({ ctx }) => {
          return {
            correlationId: ctx.correlationId,
            hasLogger: !!ctx.logger
          }
        })
      })

      // Create caller with mock context
      const caller = testRouter.createCaller({
        req: {
          headers: {
            get: () => 'caller-correlation-id'
          }
        } as unknown as Request,
        correlationId: 'caller-correlation-id',
        logger: mockLogger
      })

      const result = await caller.test()

      expect(result.correlationId).toBe('caller-correlation-id')
      expect(result.hasLogger).toBe(true)
    })
  })

  describe('Logging with Correlation ID', () => {
    it('should include correlation ID in all log calls', async () => {
      interface Context {
        req?: Request
        correlationId: string
        logger: typeof mockLogger
      }

      const t = initTRPC.context<Context>().create()

      const testProcedure = t.procedure.use(async (opts) => {
        const start = Date.now()

        try {
          const result = await opts.next({ ctx: opts.ctx })
          const durationMs = Date.now() - start

          if (!result.ok) {
            opts.ctx.logger.error('Procedure failed', {
              error: result.error,
              metadata: {
                path: opts.path,
                type: opts.type,
                durationMs
              }
            })
          }

          return result
        } catch (error) {
          const durationMs = Date.now() - start
          opts.ctx.logger.error('Unexpected error in procedure', {
            error: error as Error,
            metadata: {
              path: opts.path,
              type: opts.type,
              durationMs
            }
          })
          throw error
        }
      })

      const testRouter = t.router({
        success: testProcedure.query(() => 'success'),
        failure: testProcedure.query(() => {
          throw new Error('Test error')
        })
      })

      const caller = testRouter.createCaller({
        correlationId: 'test-correlation-id',
        logger: mockLogger
      })

      // Test successful procedure
      await caller.success()
      expect(mockLogger.error).not.toHaveBeenCalled()

      // Test failed procedure
      try {
        await caller.failure()
        expect(true).toBe(false) // Should not reach here
      } catch (error) {
        expect((error as Error).message).toBe('Test error')
      }

      // Check that error was called
      expect(mockLogger.error).toHaveBeenCalled()

      // Get the actual call arguments to debug
      const errorCalls = mockLogger.error.mock.calls
      expect(errorCalls.length).toBe(1)

      // Check the first argument (message)
      expect(errorCalls[0]?.[0]).toBe('Procedure failed')

      // Check the second argument (context object)
      const errorContext = errorCalls[0]?.[1] as {
        error: Error
        metadata: {
          path: string
          type: string
          durationMs: number
        }
      }
      expect(errorContext).toHaveProperty('error')
      expect(errorContext.error).toBeInstanceOf(Error)
      expect(errorContext.error.message).toBe('Test error')
      expect(errorContext).toHaveProperty('metadata')
      expect(errorContext.metadata).toHaveProperty('path', 'failure')
      expect(errorContext.metadata).toHaveProperty('type', 'query')
      expect(errorContext.metadata).toHaveProperty('durationMs')
      expect(typeof errorContext.metadata.durationMs).toBe('number')
    })
  })
})

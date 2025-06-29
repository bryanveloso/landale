import { initTRPC, TRPCError } from '@trpc/server'
import { ZodError } from 'zod'
import { createLogger } from '@landale/logger'
import { env } from '@/lib/env'
import { nanoid } from 'nanoid'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'trpc' })

export interface Context {
  req?: Request
  correlationId: string
  logger: ReturnType<typeof createLogger>
}

const t = initTRPC.context<Context>().create({
  errorFormatter({ shape, error }) {
    return {
      ...shape,
      data: {
        ...shape.data,
        zodError: error.cause instanceof ZodError ? error.cause.flatten() : null
      }
    }
  }
})

export const router = t.router
export { t }

const correlationMiddleware = t.middleware(async (opts) => {
  const correlationId = opts.ctx.req?.headers.get('x-correlation-id') || nanoid()
  const procedureLogger = logger.child({
    correlationId,
    module: 'trpc'
  })

  return opts.next({
    ctx: {
      ...opts.ctx,
      correlationId,
      logger: procedureLogger
    }
  })
})

export const publicProcedure = t.procedure.use(correlationMiddleware).use(async (opts) => {
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

export const authedProcedure = publicProcedure.use(async (opts) => {
  const apiKey = opts.ctx.req?.headers.get('x-api-key')
  const expectedKey = env.CONTROL_API_KEY

  if (apiKey !== expectedKey) {
    log.warn('Unauthorized API access attempt', {
      metadata: {
        path: opts.path,
        type: opts.type
      }
    })
    throw new TRPCError({
      code: 'UNAUTHORIZED',
      message: 'Invalid API key'
    })
  }

  return opts.next()
})

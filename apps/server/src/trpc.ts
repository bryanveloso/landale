import { initTRPC, TRPCError } from '@trpc/server'
import { ZodError } from 'zod'
import { createLogger } from '@landale/logger'
import { env } from '@/lib/env'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'trpc' })

export interface Context {
  req?: Request
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

export const publicProcedure = t.procedure.use(async (opts) => {
  const start = Date.now()

  try {
    const result = await opts.next({ ctx: opts.ctx })
    const durationMs = Date.now() - start

    if (!result.ok) {
      log.error('Procedure failed', {
        path: opts.path,
        type: opts.type,
        durationMs,
        error: result.error
      })
    }

    return result
  } catch (error) {
    const durationMs = Date.now() - start
    log.error('Unexpected error in procedure', {
      path: opts.path,
      type: opts.type,
      durationMs,
      error
    })
    throw error
  }
})

export const authedProcedure = publicProcedure.use(async (opts) => {
  const apiKey = opts.ctx.req?.headers?.get('x-api-key')
  const expectedKey = env.CONTROL_API_KEY

  if (apiKey !== expectedKey) {
    throw new TRPCError({
      code: 'UNAUTHORIZED',
      message: 'Invalid API key'
    })
  }

  return opts.next()
})

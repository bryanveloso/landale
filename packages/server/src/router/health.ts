import { router, publicProcedure } from '@/trpc'

export const healthRouter = router({
  check: publicProcedure.query(async () => {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      version: '0.3.0'
    }
  })
})

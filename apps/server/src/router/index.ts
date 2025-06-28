import { router } from '@/trpc'
import { controlRouter } from './control'
import { healthRouter } from './health'
import { twitchRouter } from './twitch'
import { ironmonRouter } from './ironmon'
import { displaysRouter } from './displays'
import { appleMusicRouter } from './apple-music'
import { monitoringRouter } from './monitoring'
import { agentsRouter } from './agents'

export const appRouter = router({
  health: healthRouter,
  control: controlRouter,
  twitch: twitchRouter,
  ironmon: ironmonRouter,
  displays: displaysRouter,
  appleMusic: appleMusicRouter,
  monitoring: monitoringRouter,
  agents: agentsRouter
})

export type AppRouter = typeof appRouter

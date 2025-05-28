import { router } from '@/trpc'
import { controlRouter } from './control'
import { healthRouter } from './health'
import { twitchRouter } from './twitch'
import { ironmonRouter } from './ironmon'

export const appRouter = router({
  health: healthRouter,
  control: controlRouter,
  twitch: twitchRouter,
  ironmon: ironmonRouter
})

export type AppRouter = typeof appRouter

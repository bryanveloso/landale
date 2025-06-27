import { trpcClient } from '@/lib/trpc-client'
import type { inferRouterOutputs } from '@trpc/server'
import type { AppRouter } from '@landale/server'

export type RouterOutputs = inferRouterOutputs<AppRouter>

export { trpcClient as trpc }

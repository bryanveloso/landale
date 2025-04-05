import { createTRPCContext } from '@trpc/tanstack-react-query'

import type { AppRouter } from '@landale/server/trpc'

export const { TRPCProvider, useTRPC, useTRPCClient } = createTRPCContext<AppRouter>()

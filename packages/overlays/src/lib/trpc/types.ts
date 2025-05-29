import type { createTRPCContext } from '@trpc/tanstack-react-query'
import type { AppRouter } from '@landale/server'

export type TRPCContextResult = ReturnType<typeof createTRPCContext<AppRouter>>
export type TRPCProviderType = TRPCContextResult['TRPCProvider']
export type UseTRPCType = TRPCContextResult['useTRPC']
import { QueryClient } from '@tanstack/react-query'
import { createTRPCClient, createWSClient, loggerLink, wsLink, type TRPCClient } from '@trpc/client'
import { createTRPCContext } from '@trpc/tanstack-react-query'
import type { AppRouter } from '@landale/server'
import type { TRPCProviderType, UseTRPCType } from './types'

export const queryClient = new QueryClient({
  defaultOptions: { queries: { refetchOnWindowFocus: false } }
})

// Use the same hostname as the current page to support different environments
const wsUrl = `ws://${window.location.hostname}:7175`

const wsClient = createWSClient({
  url: wsUrl,
  onOpen: () => {
    console.log(`[WebSocket] Connected to server at ${wsUrl}`)
  },
  onClose: (cause) => {
    console.log('[WebSocket] Disconnected:', cause)
  },
  retryDelayMs: (attemptIndex): number => {
    // Exponential backoff with max delay of 30 seconds
    const delays = [1000, 2000, 5000, 10000, 30000]
    return delays[Math.min(attemptIndex, delays.length - 1)]!
  },
  lazy: {
    enabled: false,
    closeMs: 0
  }
})

const trpcContext = createTRPCContext<AppRouter>()
export const TRPCProvider: TRPCProviderType = trpcContext.TRPCProvider
export const useTRPC: UseTRPCType = trpcContext.useTRPC

export const trpcClient: TRPCClient<AppRouter> = createTRPCClient<AppRouter>({
  links: [loggerLink(), wsLink({ client: wsClient })]
})
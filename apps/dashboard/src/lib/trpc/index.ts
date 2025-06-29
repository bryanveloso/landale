import type { AppRouter } from '@landale/server'
import { createTRPCClient, createWSClient, type TRPCClient, wsLink } from '@trpc/client'
import { serviceUrls } from '@/lib/config'

const wsClient = createWSClient({
  url: serviceUrls.server.ws,
  onOpen: () => {
    console.log(`[tRPC] Connected to server at ${serviceUrls.server.ws}`)
  },
  onClose: (cause) => {
    console.log('[tRPC] Disconnected:', cause)
  },
  onError: (event) => {
    console.error('[tRPC] WebSocket error:', event)
  },
  retryDelayMs: (attemptIndex): number => {
    // Shorter delays for faster reconnection
    const delays = [500, 1000, 2000, 4000, 8000]
    return delays[Math.min(attemptIndex, delays.length - 1)] ?? 8000
  },
  lazy: {
    enabled: false,
    closeMs: 0
  }
})

export const trpcClient: TRPCClient<AppRouter> = createTRPCClient<AppRouter>({
  links: [wsLink({ client: wsClient })]
})

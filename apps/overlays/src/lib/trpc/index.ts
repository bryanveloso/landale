import { createTRPCClient, createWSClient, loggerLink, wsLink, type TRPCClient } from '@trpc/client'
import type { AppRouter } from '@landale/server'
import { wsLogger } from '@/lib/logger'

// Use the same hostname as the current page to support different environments
const wsUrl = `ws://${window.location.hostname}:7175`

const wsClient = createWSClient({
  url: wsUrl,
  onOpen: () => {
    wsLogger.info('WebSocket connected to server', { url: wsUrl })
  },
  onClose: (cause) => {
    wsLogger.info('WebSocket disconnected', { 
      metadata: { 
        cause: cause?.message || 'Unknown',
        code: cause?.code 
      } 
    })
  },
  retryDelayMs: (attemptIndex): number => {
    // Exponential backoff with max delay of 30 seconds
    const delays = [1000, 2000, 5000, 10000, 30000]
    const delay = delays[Math.min(attemptIndex, delays.length - 1)]!
    if (attemptIndex > 0) {
      wsLogger.debug('WebSocket reconnecting', { 
        metadata: { attempt: attemptIndex + 1, delay } 
      })
    }
    return delay
  },
  lazy: {
    enabled: false,
    closeMs: 0
  }
})

export const trpcClient: TRPCClient<AppRouter> = createTRPCClient<AppRouter>({
  links: [loggerLink(), wsLink({ client: wsClient })]
})

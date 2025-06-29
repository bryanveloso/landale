import { createTRPCClient, createWSClient, loggerLink, wsLink, type TRPCClient } from '@trpc/client'
import type { AppRouter } from '@landale/server'
import { wsLogger } from '@/lib/logger'
import { serviceUrls } from '@/lib/config'

// Use service configuration for WebSocket URL
const wsUrl = serviceUrls.server.ws

const wsClient = createWSClient({
  url: wsUrl,
  onOpen: () => {
    wsLogger.info('WebSocket connected to server', { metadata: { url: wsUrl } })
  },
  onClose: (cause) => {
    wsLogger.info('WebSocket disconnected', {
      metadata: {
        cause: (cause as { message?: string } | undefined)?.message ?? 'Unknown',
        code: cause?.code
      }
    })
  },
  retryDelayMs: (attemptIndex): number => {
    // Exponential backoff with max delay of 30 seconds
    const delays = [1000, 2000, 5000, 10000, 30000]
    const delay = delays[Math.min(attemptIndex, delays.length - 1)] ?? 1000
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

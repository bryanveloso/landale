import { createTRPCClient, createWSClient, wsLink, type TRPCClient } from '@trpc/client'
import type { AppRouter } from '@landale/server'

const getWebSocketUrl = () => {
  const hostname = window.location.hostname
  const port = 7175
  return `ws://${hostname}:${port}/`
}

const wsClient = createWSClient({
  url: getWebSocketUrl(),
  onOpen: () => {
    console.log(`[tRPC] Connected to server at ${getWebSocketUrl()}`)
  },
  onClose: (cause) => {
    console.log('[tRPC] Disconnected:', cause)
  },
  onError: (event) => {
    console.error('[tRPC] WebSocket error:', event)
  },
  retryDelayMs: (attemptIndex): number => {
    // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
    const delays = [1000, 2000, 4000, 8000, 30000]
    return delays[Math.min(attemptIndex, delays.length - 1)]!
  },
  lazy: {
    enabled: false,
    closeMs: 0
  }
})

export const trpcClient: TRPCClient<AppRouter> = createTRPCClient<AppRouter>({
  links: [
    wsLink({
      client: wsClient
    })
  ]
})

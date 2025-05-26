/* eslint-disable react-refresh/only-export-components */
import { createTRPCClient, createWSClient, loggerLink, wsLink } from '@trpc/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { FC, PropsWithChildren, useState } from 'react'

import type { AppRouter } from '@landale/server'

import { TRPCProvider } from '@/lib/trpc'

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
  retryDelayMs: (attemptIndex) => {
    // Exponential backoff with max delay of 30 seconds
    const delays = [1000, 2000, 5000, 10000, 30000]
    return delays[Math.min(attemptIndex, delays.length - 1)]
  },
  lazy: {
    enabled: false,
    closeMs: 0
  }
})

export const QueryProvider: FC<PropsWithChildren> = ({ children }) => {
  const [trpcClient] = useState(() =>
    createTRPCClient<AppRouter>({
      links: [loggerLink(), wsLink({ client: wsClient })]
    })
  )

  return (
    <QueryClientProvider client={queryClient}>
      <TRPCProvider trpcClient={trpcClient} queryClient={queryClient}>
        {children}
      </TRPCProvider>
    </QueryClientProvider>
  )
}

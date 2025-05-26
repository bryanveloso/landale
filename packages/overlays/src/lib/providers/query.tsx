/* eslint-disable react-refresh/only-export-components */
import { createTRPCClient, createWSClient, loggerLink, wsLink } from '@trpc/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { FC, PropsWithChildren, useState } from 'react'

import type { AppRouter } from '@landale/server'

import { TRPCProvider } from '@/lib/trpc'

export const queryClient = new QueryClient({
  defaultOptions: { queries: { refetchOnWindowFocus: false } }
})

const wsClient = createWSClient({
  url: 'ws://localhost:7175',
  onOpen: () => {
    console.log('[WebSocket] Connected to server')
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

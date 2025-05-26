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
  url: 'ws://localhost:7175'
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

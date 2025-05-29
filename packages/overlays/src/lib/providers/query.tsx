import { QueryClientProvider } from '@tanstack/react-query'
import { type FC, type PropsWithChildren } from 'react'

import { queryClient, TRPCProvider, trpcClient } from '@/lib/trpc'

export const QueryProvider: FC<PropsWithChildren> = ({ children }) => {
  return (
    <TRPCProvider trpcClient={trpcClient} queryClient={queryClient}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </TRPCProvider>
  )
}
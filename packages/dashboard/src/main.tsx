import React from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { createTRPCClient, createWSClient, wsLink } from '@trpc/client'
import type { AppRouter } from '@landale/server/src/trpc'
import { TRPCProvider } from './lib/trpc'
import { routeTree } from './routeTree.gen'
import './index.css'

// Create query client
const queryClient = new QueryClient({
  defaultOptions: { 
    queries: { 
      refetchOnWindowFocus: false,
      staleTime: 30 * 1000, // 30 seconds
    } 
  }
})

// Use the same hostname as the current page  
const wsUrl = `ws://${window.location.hostname}:7175/`

// Create WebSocket client
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

// Create tRPC client
const trpcClient = createTRPCClient<AppRouter>({
  links: [
    wsLink({ client: wsClient })
  ]
})

// Create router
const router = createRouter({ routeTree })

// Register router for type safety
declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <TRPCProvider trpcClient={trpcClient} queryClient={queryClient}>
        <RouterProvider router={router} />
      </TRPCProvider>
    </QueryClientProvider>
  </React.StrictMode>
)
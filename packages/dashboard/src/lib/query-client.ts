import { QueryClient } from '@tanstack/react-query'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Since we're using WebSocket subscriptions for real-time updates,
      // we don't need aggressive refetching
      staleTime: Infinity,
      refetchOnWindowFocus: false,
      refetchOnReconnect: false,
    },
    mutations: {
      // Show errors in console during development
      onError: (error) => {
        console.error('Mutation error:', error)
      },
    },
  },
})
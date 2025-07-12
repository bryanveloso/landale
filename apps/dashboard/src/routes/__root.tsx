import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { StreamServiceProvider } from '@/services/stream-service'

export const Route = createRootRoute({
  component: () => (
    <StreamServiceProvider>
      <Outlet />
    </StreamServiceProvider>
  ),
  errorComponent: ({ error }) => (
    <div class="p-4 text-red-500">
      <h2 class="text-lg font-bold">Application Error</h2>
      <p>{error?.message || 'An unexpected error occurred'}</p>
      {import.meta.env.DEV && (
        <pre class="mt-2 text-xs bg-red-50 p-2 rounded">
          {error?.stack}
        </pre>
      )}
    </div>
  )
})

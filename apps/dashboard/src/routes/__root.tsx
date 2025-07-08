import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { StreamServiceProvider } from '../services/stream-service'

export const Route = createRootRoute({
  component: () => (
    <StreamServiceProvider>
      <Outlet />
    </StreamServiceProvider>
  )
})

import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { SocketProvider } from '@landale/shared'

export const Route = createRootRoute({
  component: () => (
    <SocketProvider serviceName="overlays">
      <Outlet />
    </SocketProvider>
  )
})

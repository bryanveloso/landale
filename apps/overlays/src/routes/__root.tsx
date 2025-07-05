import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { SocketProvider } from '../providers/socket-provider'

export const Route = createRootRoute({
  component: () => (
    <SocketProvider>
      <Outlet />
    </SocketProvider>
  )
})

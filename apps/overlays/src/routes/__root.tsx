import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { SocketProvider } from '../providers/socket-provider'
import { ConnectionIndicator } from '../components/connection-indicator'

export const Route = createRootRoute({
  component: () => (
    <SocketProvider>
      <Outlet />
      <ConnectionIndicator />
    </SocketProvider>
  )
})

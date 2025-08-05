import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { ConnectionIndicator } from '../components/connection-indicator'

export const Route = createRootRoute({
  component: () => (
    <>
      <Outlet />
      <ConnectionIndicator />
    </>
  )
})

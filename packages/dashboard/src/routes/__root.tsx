import { createRootRoute, Outlet } from '@tanstack/react-router'

export const Route = createRootRoute({
  component: () => (
    <div className="min-h-screen bg-gray-900 text-gray-100">
      <Outlet />
    </div>
  ),
})
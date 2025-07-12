import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { StreamServiceProvider } from '@/services/stream-service'
import { DashboardErrorBoundary } from '@/components/dashboard-error-boundary'

export const Route = createRootRoute({
  component: () => (
    <DashboardErrorBoundary componentName="StreamServiceProvider">
      <StreamServiceProvider>
        <Outlet />
      </StreamServiceProvider>
    </DashboardErrorBoundary>
  )
})

import { createRootRoute, Outlet } from '@tanstack/solid-router'
import { StreamServiceProvider } from '@/services/stream-service'
import { TelemetryDrawer } from '@/components/telemetry-drawer'
import { TelemetryProvider, useTelemetry } from '@/contexts/telemetry-context'

const RootLayout = () => {
  const telemetry = useTelemetry()

  return (
    <>
      <Outlet />
      <TelemetryDrawer isOpen={telemetry.isOpen()} onClose={telemetry.close} />
    </>
  )
}

export const Route = createRootRoute({
  component: () => {
    return (
      <StreamServiceProvider>
        <TelemetryProvider>
          <RootLayout />
        </TelemetryProvider>
      </StreamServiceProvider>
    )
  },
  errorComponent: ({ error }) => (
    <div class="p-4 text-red-500">
      <h2 class="text-lg font-bold">Application Error</h2>
      <p>{error?.message || 'An unexpected error occurred'}</p>
      {import.meta.env.DEV && <pre class="mt-2 rounded bg-red-50 p-2 text-xs">{error?.stack}</pre>}
    </div>
  )
})

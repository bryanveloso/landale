import { createRootRoute, Outlet, useLocation } from '@tanstack/solid-router'
import { PhoenixServiceProvider } from '@/services/phoenix-service'
import { TelemetryDrawer } from '@/components/telemetry-drawer'
import { TelemetryProvider, useTelemetry } from '@/contexts/telemetry-context'
import { Show } from 'solid-js'

const RootLayout = () => {
  const telemetry = useTelemetry()
  const location = useLocation()

  // Only show drawer on main dashboard route
  const isTelemetryPage = () => {
    const path = location().pathname
    return path === '/telemetry'
  }

  return (
    <>
      <Outlet />
      <Show when={!isTelemetryPage()}>
        <TelemetryDrawer isOpen={telemetry.isOpen()} onClose={telemetry.close} />
      </Show>
    </>
  )
}

export const Route = createRootRoute({
  component: () => {
    return (
      <PhoenixServiceProvider>
        <TelemetryProvider>
          <RootLayout />
        </TelemetryProvider>
      </PhoenixServiceProvider>
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

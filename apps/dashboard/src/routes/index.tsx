import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '@/components/stream-queue'
import { LayerStateMonitor } from '@/components/layer-state-monitor'
import { TakeoverPanel } from '@/components/takeover-panel'
import { StreamInformation } from '@/components/stream-information'
import { DebugDrawer } from '@/components/debug-drawer'
import { StatusBar } from '@/components/status-bar'
import { ConnectionMonitor } from '@/components/error-boundary'
import { ActivityLogPanel } from '@/components/activity-log-panel'
import { ConnectionTelemetry } from '@/components/connection-telemetry'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <ConnectionMonitor>
      <div class="grid h-full grid-rows-[auto_1fr_auto]" data-dashboard-layout>
        <div></div>

        <div class="flex">
          <StreamInformation />
          <TakeoverPanel />
          <StreamQueue />
          <ActivityLogPanel />
          <LayerStateMonitor />
          <ConnectionTelemetry />
        </div>

        <StatusBar />
        <DebugDrawer />
      </div>
    </ConnectionMonitor>
  )
}

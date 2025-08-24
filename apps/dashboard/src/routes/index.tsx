import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '@/components/stream-queue'
import { LayerStateMonitor } from '@/components/layer-state-monitor'
import { TakeoverPanel } from '@/components/takeover-panel'
import { StreamInformation } from '@/components/stream-information'
import { StatusBar } from '@/components/status-bar'
import { ConnectionMonitor } from '@/components/error-boundary'
import { ActivityLogPanel } from '@/components/activity'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <ConnectionMonitor>
      <div class="grid h-dvh w-dvw grid-rows-[auto_1fr_auto]">
        <div></div>

        <div class="flex">
          <ActivityLogPanel />
          <StreamInformation />
          <TakeoverPanel />
          <StreamQueue />
          <LayerStateMonitor />
        </div>

        <StatusBar />
      </div>
    </ConnectionMonitor>
  )
}

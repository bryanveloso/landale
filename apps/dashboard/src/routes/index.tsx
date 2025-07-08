import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '@/components/stream-queue'
import { LayerStateMonitor } from '@/components/layer-state-monitor'
import { EmergencyOverride } from '@/components/emergency-override'
import { StatusBar } from '@/components/status-bar'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <div class="grid h-full grid-rows-[auto_1fr_auto]" data-dashboard-layout>
      <div></div>

      <div class="flex">
        <EmergencyOverride />
        <StreamQueue />
        <LayerStateMonitor />
      </div>

      <StatusBar />
    </div>
  )
}

import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '@/components/stream-queue'
import { LayerStateMonitor } from '@/components/layer-state-monitor'
import { EmergencyOverride } from '@/components/emergency-override'
import { ConnectionStatus } from '@/components/connection-status'
import { StatusBar } from '@/components/status-bar'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <div>
      <div>
        <ConnectionStatus />
      </div>

      <div>
        <EmergencyOverride />
      </div>

      <div>
        <StreamQueue />
      </div>

      <div>
        <LayerStateMonitor />
      </div>

      <div>
        <StatusBar />
      </div>
    </div>
  )
}

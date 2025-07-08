import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '../components/stream-queue/index'
import { LayerStateMonitor } from '../components/layer-state-monitor/index'
import { EmergencyOverride } from '../components/emergency-override/index'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <div data-dashboard-layout>
      <div data-dashboard-section="override">
        <EmergencyOverride />
      </div>
      
      <div data-dashboard-section="queue">
        <StreamQueue />
      </div>
      
      <div data-dashboard-section="layers">
        <LayerStateMonitor />
      </div>
    </div>
  )
}

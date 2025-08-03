import { ConnectionStatus } from './connection-status'
import { SystemStatus } from './system-status'
import { TelemetryIndicator } from './telemetry-indicator'

export function StatusBar() {
  return (
    <div class="bg-shadow flex items-center justify-between px-4 py-3 text-xs">
      <div class="flex items-center gap-4">
        <ConnectionStatus />
        <SystemStatus />
      </div>
      <TelemetryIndicator />
    </div>
  )
}

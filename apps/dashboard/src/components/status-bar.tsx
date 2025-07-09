import { ConnectionStatus } from './connection-status'
import { SystemStatus } from './system-status'

export function StatusBar() {
  return (
    <div class="bg-shadow px-4 py-3 text-xs">
      <ConnectionStatus />
      <SystemStatus />
    </div>
  )
}

import { ConnectionStatus } from "./connection-status";

export function StatusBar() {
  return (
    <div class="bg-shadow px-4 py-3 text-xs">
      <ConnectionStatus />
    </div>
  )
}

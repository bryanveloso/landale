import { ConnectionStatus } from "./connection-status";

export function StatusBar() {
  return (
    <div class="w-full bg-red-500">
      <ConnectionStatus />
    </div>
  )
}

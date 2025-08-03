/**
 * Telemetry Indicator Component
 *
 * Small indicator that shows telemetry is available and provides quick access.
 */

import { useTelemetry } from '@/contexts/telemetry-context'

export function TelemetryIndicator() {
  const telemetry = useTelemetry()

  return (
    <button
      onClick={() => telemetry.toggle()}
      class="flex items-center gap-1 rounded px-2 py-0.5 text-[10px] text-gray-500 transition-colors hover:bg-gray-800 hover:text-gray-300"
      title="System Telemetry (Ctrl+Shift+T)">
      <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
        />
      </svg>
      <span>Telemetry</span>
    </button>
  )
}

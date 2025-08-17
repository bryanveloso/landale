import { ConnectionStatus } from './connection-status'
import { SystemStatus } from './system-status'
import { Link } from '@tanstack/solid-router'

export function StatusBar() {
  return (
    <div class="bg-shadow flex items-center justify-between px-4 py-3 text-xs">
      <div class="flex items-center gap-4">
        <ConnectionStatus />
        <SystemStatus />
        <div class="ml-4 flex items-center gap-2">
          <Link href="/" class="text-gray-400 transition-colors hover:text-white">
            Dashboard
          </Link>
          <span class="text-gray-600">|</span>
          <Link href="/oauth" class="text-gray-400 transition-colors hover:text-white">
            OAuth
          </Link>
          <span class="text-gray-600">|</span>
          <Link href="/service-status" class="text-gray-400 transition-colors hover:text-white">
            Service Status
          </Link>
          <span class="text-gray-600">|</span>
          <Link href="/correlations" class="text-gray-400 transition-colors hover:text-white">
            Correlations
          </Link>
        </div>
      </div>
    </div>
  )
}

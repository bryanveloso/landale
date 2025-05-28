import { Activity, CheckCircle, XCircle, Wifi, WifiOff } from 'lucide-react'
import { useSubscription } from '@/hooks/use-subscription'
import type { SystemStatus as SystemStatusType } from '@/types'

export function SystemStatus() {
  const {
    data: status,
    connectionState,
    isConnected,
    isError
  } = useSubscription<SystemStatusType>('control.system.onStatusUpdate')

  const getStatusIcon = () => {
    if (isError) return <XCircle className="h-5 w-5 text-red-500" />
    if (!isConnected) return <WifiOff className="h-5 w-5 text-gray-500" />
    return <CheckCircle className="h-5 w-5 text-green-500" />
  }

  const getStatusText = () => {
    if (isError) return 'Connection error'
    if (!isConnected) return 'Connecting...'
    return 'System Status'
  }

  const getConnectionIndicator = () => {
    const state = connectionState.state
    if (state === 'connected') return <Wifi className="h-4 w-4 text-green-500" />
    if (state === 'error') return <WifiOff className="h-4 w-4 text-red-500" />
    return <Activity className="h-4 w-4 animate-pulse text-gray-500" />
  }

  return (
    <div className="rounded-lg bg-gray-800 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="flex items-center gap-2 text-xl font-semibold">
          {getStatusIcon()}
          {getStatusText()}
        </h2>
        {getConnectionIndicator()}
      </div>

      {isError && <div className="text-sm text-red-400">{connectionState.error || 'Unable to connect to server'}</div>}

      {isConnected && status && (
        <div className="space-y-3">
          <div>
            <div className="text-sm text-gray-400">Status</div>
            <div className="font-medium text-green-400 uppercase">{status.status}</div>
          </div>

          <div>
            <div className="text-sm text-gray-400">Uptime</div>
            <div className="font-medium">{status.uptime.formatted}</div>
          </div>

          <div>
            <div className="text-sm text-gray-400">Memory Usage</div>
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-400">Heap</span>
                <span>
                  {status.memory.heapUsed} / {status.memory.heapTotal}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">RSS</span>
                <span>{status.memory.rss}</span>
              </div>
            </div>
          </div>

          <div>
            <div className="text-sm text-gray-400">Version</div>
            <div className="font-mono text-sm">{status.version}</div>
          </div>
        </div>
      )}
    </div>
  )
}

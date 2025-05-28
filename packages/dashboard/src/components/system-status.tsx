import { Activity, CheckCircle, XCircle, Wifi, WifiOff } from 'lucide-react'
import { useSubscription } from '@/hooks/use-subscription'
import type { SystemStatus as SystemStatusType } from '@/types'

export function SystemStatus() {
  const { data: status, connectionState, isConnected, isError } = useSubscription<SystemStatusType>(
    'control.system.onStatusUpdate'
  )

  const getStatusIcon = () => {
    if (isError) return <XCircle className="w-5 h-5 text-red-500" />
    if (!isConnected) return <WifiOff className="w-5 h-5 text-gray-500" />
    return <CheckCircle className="w-5 h-5 text-green-500" />
  }

  const getStatusText = () => {
    if (isError) return 'Connection error'
    if (!isConnected) return 'Connecting...'
    return 'System Status'
  }

  const getConnectionIndicator = () => {
    const state = connectionState.state
    if (state === 'connected') return <Wifi className="w-4 h-4 text-green-500" />
    if (state === 'error') return <WifiOff className="w-4 h-4 text-red-500" />
    return <Activity className="w-4 h-4 text-gray-500 animate-pulse" />
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          {getStatusIcon()}
          {getStatusText()}
        </h2>
        {getConnectionIndicator()}
      </div>
      
      {isError && (
        <div className="text-red-400 text-sm">
          {connectionState.error || 'Unable to connect to server'}
        </div>
      )}

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
            <div className="text-sm space-y-1">
              <div className="flex justify-between">
                <span className="text-gray-400">Heap</span>
                <span>{status.memory.heapUsed} / {status.memory.heapTotal}</span>
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
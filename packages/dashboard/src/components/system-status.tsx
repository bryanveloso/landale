import { useEffect, useState } from 'react'
import { useTRPCClient } from '../lib/trpc'
import { Activity, CheckCircle, XCircle } from 'lucide-react'

export function SystemStatus() {
  const trpcClient = useTRPCClient()
  const [status, setStatus] = useState<any>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<any>(null)
  
  useEffect(() => {
    const subscription = trpcClient.control.system.onStatusUpdate.subscribe(undefined, {
      onData: (data) => {
        setStatus(data)
        setIsLoading(false)
        setError(null)
      },
      onError: (err) => {
        setError(err)
        setIsLoading(false)
      }
    })
    
    return () => {
      subscription.unsubscribe()
    }
  }, [trpcClient])

  if (isLoading) {
    return (
      <div className="bg-gray-800 rounded-lg p-6">
        <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
          <Activity className="w-5 h-5" />
          System Status
        </h2>
        <div className="text-gray-400">Loading...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="bg-gray-800 rounded-lg p-6">
        <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
          <XCircle className="w-5 h-5 text-red-500" />
          System Status
        </h2>
        <div className="text-red-400">Connection error</div>
      </div>
    )
  }

  // const status is already defined above
  
  if (!status) {
    return null
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
        <CheckCircle className="w-5 h-5 text-green-500" />
        System Status
      </h2>
      
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
    </div>
  )
}
import { useEffect, useState, useCallback } from 'react'
import { useSubscription } from '@/hooks/use-subscription'

interface StreamStatus {
  isLive: boolean
  streamTitle?: string
  gameName?: string
  viewerCount?: number
  startedAt?: Date
  uptime?: string
}

export function StreamStatus() {
  const [streamStatus, setStreamStatus] = useState<StreamStatus>({ isLive: false })

  // Memoize callbacks to prevent infinite re-renders
  const handleStreamOnline = useCallback((data: any) => {
    console.log('Stream went online:', data)
    setStreamStatus({
      isLive: true,
      streamTitle: data.type || 'Live Stream',
      startedAt: data.startDate ? new Date(data.startDate) : new Date()
    })
  }, [])

  const handleStreamOffline = useCallback(() => {
    console.log('Stream went offline')
    setStreamStatus({
      isLive: false,
      streamTitle: undefined,
      gameName: undefined,
      viewerCount: undefined,
      startedAt: undefined,
      uptime: undefined
    })
  }, [])

  const handleError = useCallback((error: Error, type: string) => {
    console.error(`${type} subscription error:`, error)
  }, [])

  // Subscribe to stream online events
  const { isConnected: onlineConnected, error: onlineError } = useSubscription('twitch.onStreamOnline', undefined, {
    onData: handleStreamOnline,
    onError: (error) => handleError(error, 'Stream online')
  })

  // Subscribe to stream offline events
  const { isConnected: offlineConnected, error: offlineError } = useSubscription('twitch.onStreamOffline', undefined, {
    onData: handleStreamOffline,
    onError: (error) => handleError(error, 'Stream offline')
  })

  // Calculate uptime
  useEffect(() => {
    if (!streamStatus.isLive || !streamStatus.startedAt) return

    const interval = setInterval(() => {
      const now = new Date()
      const diff = now.getTime() - streamStatus.startedAt!.getTime()
      const hours = Math.floor(diff / (1000 * 60 * 60))
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60))
      const seconds = Math.floor((diff % (1000 * 60)) / 1000)

      setStreamStatus((prev) => ({
        ...prev,
        uptime: `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
      }))
    }, 1000)

    return () => clearInterval(interval)
  }, [streamStatus.isLive, streamStatus.startedAt])

  const isConnected = onlineConnected && offlineConnected

  return (
    <div className="rounded-lg border border-gray-700 bg-gray-800 p-6">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-100">Stream Status</h2>
        <div className="flex items-center gap-2">
          <div className={`h-2 w-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
          <span className="text-xs text-gray-400">{isConnected ? 'Connected' : 'Disconnected'}</span>
        </div>
      </div>

      <div className="mt-4">
        <div className="flex items-center gap-3">
          <div className={`h-4 w-4 rounded-full ${streamStatus.isLive ? 'animate-pulse bg-red-500' : 'bg-gray-500'}`} />
          <span className={`text-lg font-medium ${streamStatus.isLive ? 'text-red-400' : 'text-gray-400'}`}>
            {streamStatus.isLive ? 'LIVE' : 'OFFLINE'}
          </span>
        </div>

        {/* Debug info */}
        {(onlineError || offlineError) && (
          <div className="mt-2 text-xs text-red-400">Error: Check console for details</div>
        )}

        {streamStatus.isLive && (
          <div className="mt-4 space-y-2">
            {streamStatus.streamTitle && (
              <div>
                <span className="text-sm text-gray-400">Title: </span>
                <span className="text-sm text-gray-200">{streamStatus.streamTitle}</span>
              </div>
            )}

            {streamStatus.uptime && (
              <div>
                <span className="text-sm text-gray-400">Uptime: </span>
                <span className="font-mono text-sm text-gray-200">{streamStatus.uptime}</span>
              </div>
            )}

            {streamStatus.startedAt && (
              <div>
                <span className="text-sm text-gray-400">Started: </span>
                <span className="text-sm text-gray-200">{streamStatus.startedAt.toLocaleTimeString()}</span>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

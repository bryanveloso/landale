import { useEffect, useRef, useState } from 'react'
import { useSubscription } from '@/hooks/use-subscription'
import { MessageSquare, Zap, Settings, Gamepad2, Wifi, WifiOff } from 'lucide-react'

interface ActivityItem {
  id: string
  type: string
  timestamp: string
  data: unknown
}

export function ActivityFeed() {
  const [activities, setActivities] = useState<ActivityItem[]>([])
  const containerRef = useRef<HTMLDivElement>(null)

  const { isConnected, isError } = useSubscription<ActivityItem>('control.stream.activity', undefined, {
    onData: (activity) => {
      setActivities((prev) => {
        const newActivities = [activity, ...prev].slice(0, 50) // Keep last 50
        return newActivities
      })
    }
  })

  // Auto-scroll to top when new activity arrives
  useEffect(() => {
    if (containerRef.current && activities.length > 0) {
      containerRef.current.scrollTop = 0
    }
  }, [activities])

  const getActivityIcon = (type: string) => {
    if (type.startsWith('twitch:')) return <MessageSquare className="h-4 w-4 text-purple-400" />
    if (type.startsWith('ironmon:')) return <Gamepad2 className="h-4 w-4 text-blue-400" />
    if (type.includes('config')) return <Settings className="h-4 w-4 text-green-400" />
    return <Zap className="h-4 w-4 text-yellow-400" />
  }

  const formatActivityType = (type: string) => {
    return type
      .split(':')
      .slice(-1)[0]
      .replace(/([A-Z])/g, ' $1')
      .trim()
  }

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp)
    return date.toLocaleTimeString()
  }

  const getConnectionIndicator = () => {
    if (isError) return <WifiOff className="h-4 w-4 text-red-500" />
    if (isConnected) return <Wifi className="h-4 w-4 text-green-500" />
    return <div className="h-4 w-4 animate-pulse rounded-full bg-gray-500" />
  }

  return (
    <div className="rounded-lg bg-gray-800 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-xl font-semibold">Activity Feed</h2>
        {getConnectionIndicator()}
      </div>

      {isError && <div className="mb-4 text-sm text-red-400">Unable to connect to activity stream</div>}

      <div ref={containerRef} className="max-h-96 space-y-2 overflow-y-auto">
        {activities.length === 0 ? (
          <div className="py-8 text-center text-gray-400">
            {isConnected ? 'Waiting for activity...' : 'Connecting...'}
          </div>
        ) : (
          activities.map((activity) => (
            <div key={activity.id} className="flex items-start gap-3 rounded-md bg-gray-700/50 p-3">
              <div className="mt-0.5">{getActivityIcon(activity.type)}</div>

              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium capitalize">{formatActivityType(activity.type)}</span>
                  <span className="text-xs text-gray-500">{formatTimestamp(activity.timestamp)}</span>
                </div>

                <div className="mt-1 truncate text-sm text-gray-400">{JSON.stringify(activity.data)}</div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  )
}

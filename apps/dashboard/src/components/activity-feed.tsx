import { useEffect, useRef, useState } from 'react'
import { useSubscription } from '@/hooks/use-subscription'
import { Wifi, WifiOff } from 'lucide-react'
import type { ActivityEvent } from '@landale/server'
import { ActivityItem } from './activity-feed/activity-item'

export function ActivityFeed() {
  const [activities, setActivities] = useState<ActivityEvent[]>([])
  const containerRef = useRef<HTMLDivElement>(null)

  const { isConnected, isError } = useSubscription<ActivityEvent>('control.stream.activity', undefined, {
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
          activities.map((activity) => <ActivityItem key={activity.id} activity={activity} />)
        )}
      </div>
    </div>
  )
}

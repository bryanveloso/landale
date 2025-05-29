import { createFileRoute } from '@tanstack/react-router'
import { SystemStatus } from '@/components/system-status'
import { EmoteRainControl } from '@/components/emote-rain-control'
// import { ActivityFeed } from '@/components/activity-feed'

export const Route = createFileRoute('/')({
  component: Dashboard
})

function Dashboard() {
  return (
    <div className="container mx-auto p-6">
      <header className="mb-8">
        <h1 className="text-4xl font-bold text-gray-100">Landale Control</h1>
        <p className="mt-2 text-gray-400">Stream overlay management dashboard</p>
      </header>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* System Status */}
        <div className="lg:col-span-1">
          <SystemStatus />
        </div>

        {/* Main Controls */}
        <div className="space-y-6 lg:col-span-2">
          <EmoteRainControl />
        </div>

        {/* Activity Feed - TODO: Fix subscriptions */}
        {/* <div className="lg:col-span-3">
          <ActivityFeed />
        </div> */}
      </div>
    </div>
  )
}

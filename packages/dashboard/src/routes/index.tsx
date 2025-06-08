import { createFileRoute } from '@tanstack/react-router'
import { SystemStatus } from '@/components/system-status'
import { StreamStatus } from '@/components/stream-status'
import { EmoteRainControl } from '@/components/emote-rain-control'
import { ActivityFeed } from '@/components/activity-feed'
import { OBSDashboard } from '@/components/obs-dashboard'
import { StatusBarControls } from '@/components/status-bar-controls'
import { StatusTextControls } from '@/components/status-text-controls'
import { FollowerCountControl } from '@/components/follower-count-control'
import { RainwaveControl } from '@/components/rainwave-control'
import { AppleMusicControl } from '@/components/apple-music-control'

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
        <div className="space-y-6 lg:col-span-1">
          <SystemStatus />
          <StreamStatus />
        </div>

        {/* Main Controls */}
        <div className="space-y-6 lg:col-span-2">
          <StatusBarControls />
          <StatusTextControls />
          <FollowerCountControl />
          <RainwaveControl />
          <AppleMusicControl />
          <EmoteRainControl />
          <OBSDashboard />
        </div>

        {/* Activity Feed */}
        <div className="lg:col-span-3">
          <ActivityFeed />
        </div>
      </div>
    </div>
  )
}

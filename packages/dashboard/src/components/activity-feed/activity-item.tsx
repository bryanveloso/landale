import type { ActivityEvent } from '@landale/server'
import { MessageSquare, Zap, Settings, Gamepad2 } from 'lucide-react'
import { TwitchMessageActivity } from './twitch-message'
import { TwitchCheerActivity } from './twitch-cheer'
import { IronmonInitActivity } from './ironmon-init'
import { IronmonCheckpointActivity } from './ironmon-checkpoint'
import { IronmonSeedActivity } from './ironmon-seed'
import { ConfigUpdateActivity } from './config-update'
import { DefaultActivity } from './default'

interface ActivityItemProps {
  activity: ActivityEvent
}

export function ActivityItem({ activity }: ActivityItemProps) {
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
      ?.replace(/([A-Z])/g, ' $1')
      .trim() || type
  }

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp)
    return date.toLocaleTimeString()
  }

  const renderActivityContent = () => {
    switch (activity.type) {
      case 'twitch:message':
        return <TwitchMessageActivity data={activity.data} />
      
      case 'twitch:cheer':
        return <TwitchCheerActivity data={activity.data} />
      
      case 'ironmon:init':
        return <IronmonInitActivity data={activity.data} />
      
      case 'ironmon:checkpoint':
        return <IronmonCheckpointActivity data={activity.data} />
      
      case 'ironmon:seed':
        return <IronmonSeedActivity data={activity.data} />
      
      case 'config:emoteRain:updated':
        return <ConfigUpdateActivity data={activity.data} />
      
      default:
        return <DefaultActivity data={activity.data} />
    }
  }

  return (
    <div className="flex items-start gap-3 rounded-md bg-gray-700/50 p-3">
      <div className="mt-0.5">{getActivityIcon(activity.type)}</div>

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium capitalize">{formatActivityType(activity.type)}</span>
          <span className="text-xs text-gray-500">{formatTimestamp(activity.timestamp)}</span>
        </div>

        <div className="mt-1 text-sm text-gray-400">
          {renderActivityContent()}
        </div>
      </div>
    </div>
  )
}
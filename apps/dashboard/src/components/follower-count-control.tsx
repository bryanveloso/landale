import { useDisplay } from '@/hooks/use-display'
import { UserPlus, Target } from 'lucide-react'

interface FollowerCountData {
  current: number
  goal: number
  label: string
}

export function FollowerCountControl() {
  const { data, update } = useDisplay<FollowerCountData>('followerCount')

  if (!data) return null

  const percentage = (data.current / data.goal) * 100

  return (
    <div className="rounded-lg border border-gray-700 bg-gray-800 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-lg font-semibold text-gray-100">Follower Goal</h3>
        <UserPlus className="h-5 w-5 text-blue-500" />
      </div>

      <div className="space-y-4">
        {/* Progress Bar */}
        <div>
          <div className="mb-2 flex justify-between text-sm">
            <span className="text-gray-400">{data.current} followers</span>
            <span className="text-gray-400">{data.goal} goal</span>
          </div>
          <div className="h-4 w-full rounded-full bg-gray-700">
            <div
              className="h-4 rounded-full bg-gradient-to-r from-blue-500 to-purple-500 transition-all duration-500"
              style={{ width: `${Math.min(percentage, 100)}%` }}
            />
          </div>
          <p className="mt-2 text-center text-sm text-gray-400">{percentage.toFixed(1)}% complete</p>
        </div>

        {/* Quick Actions */}
        <div className="flex gap-2">
          <button
            onClick={() => update({ current: data.current + 1 })}
            className="flex-1 rounded-lg bg-green-600 px-3 py-2 text-sm text-white hover:bg-green-700">
            +1 Follower
          </button>
          <button
            onClick={() => update({ current: Math.max(0, data.current - 1) })}
            className="flex-1 rounded-lg bg-red-600 px-3 py-2 text-sm text-white hover:bg-red-700">
            -1 Follower
          </button>
        </div>

        {/* Goal Input */}
        <div className="flex items-center gap-2">
          <Target className="h-4 w-4 text-gray-400" />
          <input
            type="number"
            value={data.goal}
            onChange={(e) => update({ goal: parseInt(e.target.value) || 0 })}
            className="flex-1 rounded-lg bg-gray-700 px-3 py-2 text-sm text-gray-100"
            placeholder="Goal"
          />
        </div>
      </div>
    </div>
  )
}

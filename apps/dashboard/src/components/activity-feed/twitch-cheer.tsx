import { Sparkles } from 'lucide-react'

interface TwitchCheerData {
  username?: string
  bits?: number
  message?: string
}

export function TwitchCheerActivity({ data }: { data: unknown }) {
  const cheerData = data as TwitchCheerData

  return (
    <div className="flex items-center gap-2">
      <Sparkles className="h-4 w-4 text-purple-500" />
      <span className="font-medium text-purple-400">{cheerData.username || 'User'}</span>
      <span>cheered</span>
      <span className="font-bold text-purple-300">{cheerData.bits || 0} bits!</span>
      {cheerData.message && <span className="ml-2 text-gray-300">{cheerData.message}</span>}
    </div>
  )
}

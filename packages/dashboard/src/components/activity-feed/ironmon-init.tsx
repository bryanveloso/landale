import { Play } from 'lucide-react'

interface IronmonInitData {
  romName?: string
  version?: string
  seed?: string
}

export function IronmonInitActivity({ data }: { data: unknown }) {
  const initData = data as IronmonInitData
  
  return (
    <div className="flex items-center gap-2">
      <Play className="h-4 w-4 text-blue-400" />
      <span>IronMON initialized:</span>
      <span className="font-medium text-blue-300">{initData.romName || 'Unknown ROM'}</span>
      {initData.version && (
        <span className="text-xs text-gray-500">v{initData.version}</span>
      )}
    </div>
  )
}
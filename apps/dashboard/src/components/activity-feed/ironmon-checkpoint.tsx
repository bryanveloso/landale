import { MapPin } from 'lucide-react'

interface IronmonCheckpointData {
  name?: string
  location?: string
  time?: string
}

export function IronmonCheckpointActivity({ data }: { data: unknown }) {
  const checkpointData = data as IronmonCheckpointData

  return (
    <div className="flex items-center gap-2">
      <MapPin className="h-4 w-4 text-blue-400" />
      <span>Checkpoint reached:</span>
      <span className="font-medium text-blue-300">{checkpointData.name || 'Unknown'}</span>
      {checkpointData.location && <span className="text-xs text-gray-500">at {checkpointData.location}</span>}
    </div>
  )
}

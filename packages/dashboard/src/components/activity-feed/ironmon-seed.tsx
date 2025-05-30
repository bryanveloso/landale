import { Hash } from 'lucide-react'

interface IronmonSeedData {
  seed?: string | number
  attempts?: number
}

export function IronmonSeedActivity({ data }: { data: unknown }) {
  const seedData = data as IronmonSeedData
  
  return (
    <div className="flex items-center gap-2">
      <Hash className="h-4 w-4 text-blue-400" />
      <span>New seed:</span>
      <code className="rounded bg-gray-700 px-2 py-0.5 font-mono text-xs text-blue-300">
        {seedData.seed || 'Unknown'}
      </code>
      {seedData.attempts && (
        <span className="text-xs text-gray-500">Attempt #{seedData.attempts}</span>
      )}
    </div>
  )
}
import { Settings2 } from 'lucide-react'

interface ConfigUpdateData {
  field?: string
  oldValue?: unknown
  newValue?: unknown
}

export function ConfigUpdateActivity({ data }: { data: unknown }) {
  const configData = data as ConfigUpdateData

  if (configData.field) {
    return (
      <div className="flex items-center gap-2">
        <Settings2 className="h-4 w-4 text-green-400" />
        <span>Configuration updated:</span>
        <span className="font-medium text-green-300">{configData.field}</span>
        {configData.oldValue !== undefined && configData.newValue !== undefined && (
          <>
            <span className="text-gray-500">from</span>
            <code className="text-xs text-gray-400">{String(configData.oldValue)}</code>
            <span className="text-gray-500">to</span>
            <code className="text-xs text-green-300">{String(configData.newValue)}</code>
          </>
        )}
      </div>
    )
  }

  return (
    <div className="flex items-center gap-2">
      <Settings2 className="h-4 w-4 text-green-400" />
      <span>Emote rain configuration updated</span>
    </div>
  )
}

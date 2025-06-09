interface DefaultData {
  message?: string
  name?: string
  type?: string
  [key: string]: unknown
}

export function DefaultActivity({ data }: { data: unknown }) {
  const defaultData = data as DefaultData

  // Try to extract meaningful information
  if (defaultData.message) {
    return <span>{String(defaultData.message)}</span>
  }

  if (defaultData.name) {
    return <span>{String(defaultData.name)}</span>
  }

  if (defaultData.type) {
    return <span>{String(defaultData.type)}</span>
  }

  // Fallback to JSON preview
  const jsonString = JSON.stringify(data)
  const preview = jsonString.length > 100 ? jsonString.slice(0, 100) + '...' : jsonString

  return (
    <code className="block overflow-hidden rounded bg-gray-700 px-2 py-0.5 font-mono text-xs text-ellipsis whitespace-nowrap">
      {preview}
    </code>
  )
}

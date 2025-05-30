interface TwitchMessageData {
  username?: string
  message?: string
  emotes?: Array<{ id: string; name: string }>
}

export function TwitchMessageActivity({ data }: { data: unknown }) {
  const messageData = data as TwitchMessageData
  
  return (
    <div className="flex items-start gap-2">
      <span className="font-medium text-purple-400">{messageData.username || 'User'}:</span>
      <span className="flex-1 break-words">{messageData.message || 'Chat message'}</span>
    </div>
  )
}
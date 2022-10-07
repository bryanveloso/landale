import { useQuery } from '@tanstack/react-query'
import { HelixChannel } from '@twurple/api/lib'
import { useEffect, useState } from 'react'

import { TwitchEvent } from '~/lib'
import { useTwitchEvent } from './use-twitch-event'

export const useChannel = () => {
  const { data } = useQuery<HelixChannel>(['channel'], async () => {
    const res = await fetch('/api/channel')
    return await res.json()
  })

  const [game, setGame] = useState(data?.gameName)
  useEffect(() => {
    setGame(data?.gameName)
  }, [data])

  const handleTwitchEvent = (event: TwitchEvent) => {
    if (event.type === 'channel.update') {
      setGame(event.event.category_name)
    }
  }
  useTwitchEvent(handleTwitchEvent)

  return { data: { ...(data ?? {}), game } }
}

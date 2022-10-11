import { useQuery } from '@tanstack/react-query'
import { HelixChannel } from '@twurple/api/lib'
import { useEffect, useState } from 'react'
import axios from 'redaxios'

import { TwitchEvent } from '~/lib'
import { useTwitchEvent } from './use-twitch-event'

export interface ChannelResponse {
  data: {
    game?: string
    gameId?: string
    title?: string
  }
}

export const useChannel = (): ChannelResponse => {
  const { data } = useQuery<HelixChannel>(['channel'], async () => {
    return await (
      await axios.get('/api/channel')
    ).data
  })

  const [game, setGame] = useState(data?.gameName)
  const [gameId, setGameId] = useState(data?.gameId)
  const [title, setTitle] = useState(data?.title)

  useEffect(() => {
    setGame(data?.gameName)
    setGameId(data?.gameId)
    setTitle(data?.title)
  }, [data])

  const handleTwitchEvent = (event: TwitchEvent) => {
    if (event.type === 'channel.update') {
      setGame(event.event.category_name)
      setGameId(event.event.category_id)
      setTitle(event.event.title)
    }
  }
  useTwitchEvent(handleTwitchEvent)

  return { data: { game, gameId, title } }
}

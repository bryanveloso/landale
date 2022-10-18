import { useQuery } from '@tanstack/react-query'
import { HelixStream } from '@twurple/api/lib'
import { useEffect, useState } from 'react'
import axios from 'redaxios'

import { TwitchEvent } from '~/lib'
import { useTwitchEvent } from './use-twitch-event'

export interface StreamResponse {
  data: {
    startDate?: string
  }
}

export const useStream = (): StreamResponse => {
  const { data } = useQuery(
    ['stream'],
    async () => {
      return await(await axios.get('/api/stream')).data
    }
  )

  const [startDate, setStartDate] = useState<string | undefined>(
    data?.startDate
  )

  useEffect(() => {
    setStartDate(data?.startDate)
  }, [data])

  const handleTwitchEvent = (event: TwitchEvent) => {
    switch (event.type) {
      case 'stream.offline':
        setStartDate(undefined)
        break
      case 'stream.online':
        setStartDate(event.event.started_at)
        break

      default:
        break
    }
  }
  useTwitchEvent(handleTwitchEvent)

  return { data: { startDate } }
}

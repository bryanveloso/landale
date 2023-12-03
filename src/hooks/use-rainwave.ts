'use client'

import type {
  RainwaveEventSong,
  RainwaveResponseTypes,
} from 'rainwave-websocket-sdk'
import axios from 'redaxios'
import { useQuery } from '@tanstack/react-query'

import type { RainwaveResponse } from '@/@types/rainwave'

export const useRainwave = () => {
  const queryFn = async (): Promise<RainwaveResponse> => {
    return (
      await axios.get<RainwaveResponseTypes>('https://rainwave.cc/api4/info', {
        params: {
          sid: 1,
          user_id: process.env.NEXT_PUBLIC_RAINWAVE_USER_ID,
          key: process.env.NEXT_PUBLIC_RAINWAVE_KEY,
        },
      })
    ).data
  }

  const { data, status } = useQuery({
    queryKey: ['rainwave'],
    queryFn,
    refetchInterval: 10000,
    refetchIntervalInBackground: true,
  })

  return {
    data,
    isTunedIn: data?.user.tuned_in,
    status,
    song: data?.sched_current.songs[0],
  }
}

import axios from 'redaxios'
import type {
  RainwaveEvent,
  RainwaveEventSong,
  RequestLine,
  AlbumDiff,
  User,
  AllStationsInfo,
} from 'rainwave-websocket-sdk'
import type { ApiInfo } from 'rainwave-websocket-sdk/dist/types'
import {
  HydrationBoundary,
  QueryClient,
  dehydrate,
  useQuery,
} from '@tanstack/react-query'
import { useEffect, useState } from 'react'

import { RainwaveClient } from './rainwave.client'

export interface RainwaveResponse {
  album_diff: AlbumDiff
  all_stations_info: AllStationsInfo
  api_info: ApiInfo
  request_line: RequestLine
  sched_current: RainwaveEvent
  sched_history: RainwaveEvent
  sched_next: RainwaveEvent
  user: User
}

export const getRainwave = async (): Promise<RainwaveResponse> => {
  return await (
    await axios.get('https://rainwave.cc/api4/info', {
      params: { sid: 1, user_id: 53109, key: 'vYyXHv30AT' },
    })
  ).data
}

export const Rainwave = async () => {
  const queryClient = new QueryClient()

  await queryClient.prefetchQuery({
    queryKey: ['rainwave'],
    queryFn: getRainwave,
  })

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <RainwaveClient />
    </HydrationBoundary>
  )
}

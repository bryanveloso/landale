import axios from 'redaxios'
import type { RainwaveResponseTypes } from 'rainwave-websocket-sdk'

import type { RainwaveResponse } from '@/@types/rainwave'

import { RainwaveClient } from './rainwave.client'

export const getRainwave = async (): Promise<RainwaveResponse> => {
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

export const Rainwave = async () => {
  return <RainwaveClient />
}

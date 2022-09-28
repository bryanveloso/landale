import { createContext, FC, PropsWithChildren, useContext } from 'react'
import axios from 'redaxios'
import useSWR from 'swr'

import { HelixChannelRawDataObject } from '../twitch.types'

export interface ContextTypes {
  channel?: HelixChannelRawDataObject
}

export const ChannelContext = createContext<ContextTypes>(undefined!)

const fetcher = (url: string) => axios.get(url).then(res => res.data)

export const ChannelProvider: FC<PropsWithChildren> = ({ children }) => {
  const { data: channel } = useSWR<HelixChannelRawDataObject>(
    '/api/channel',
    fetcher
  )

  return (
    <ChannelContext.Provider value={{ channel }}>
      {children}
    </ChannelContext.Provider>
  )
}

export const useChannel = () => useContext(ChannelContext)

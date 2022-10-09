import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
import { useEffect, useState } from 'react'
import { Logomark } from '~/components/icons'

import { MenuBar, Wallpaper } from '~/components/overlays'
import {
  Controls,
  Sidebar,
  TitleBar,
  Window
} from '~/components/overlays/windows'
import { useTwitchEvent } from '~/hooks'
import {
  TwitchChannelUpdateEvent,
  TwitchEvent,
  TwitchStreamOfflineEvent,
  TwitchStreamOnlineEvent
} from '~/lib'
import { logger } from '~/logger'

type TwitchStatusEvent =
  | TwitchChannelUpdateEvent
  | TwitchStreamOfflineEvent
  | TwitchStreamOnlineEvent

const Background = ({}: InferGetServerSidePropsType<
  typeof getServerSideProps
>) => {
  const [timestamp, setTimestamp] = useState('')

  useTwitchEvent((twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key } as TwitchStatusEvent

    switch (event.type) {
      case 'stream.offline':
        logger.info('stream.offline', event)
        setTimestamp('')
        break
      case 'stream.online':
        logger.info('stream.online', event)
        const { started_at } = event.event
        setTimestamp(started_at)
        break
      default:
        break
    }
  })

  return (
    <div className="relative w-[1920px] h-[1080px] bg-black">
      <MenuBar />
      <Window>
        <div className="absolute w-full h-full rounded-lg ring-1 ring-offset-0 ring-inset ring-white/10 z-50" />
        <Controls />
        <TitleBar />
        <div className="grid grid-cols-[92px_196px_1600px] h-full">
          <div className="flex flex-col h-full bg-gradient-to-b from-black/50 to-black/30 shadow-sidebar-inset rounded-l-lg">
            <div className="grow"></div>
            <div className="py-6 text-white">
              <Logomark className="h-10 mx-auto opacity-10" />
            </div>
          </div>
          <Sidebar />
          <div className="bg-black/90 rounded-r-lg" />
        </div>
      </Window>
      <Wallpaper />
    </div>
  )
}

export const getServerSideProps: GetServerSideProps = async context => {
  return {
    props: {
      debug: context.query.debug === 'true'
    }
  }
}

export default Background

import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
import { useEffect, useState } from 'react'

import { MenuBar, Wallpaper } from '~/components/overlays'
<<<<<<< HEAD
import {
  Controls,
  Sidebar,
  TitleBar,
  Window
} from '~/components/overlays/windows'
=======
import { Controls, TitleBar, Sidebar, Window } from '~/components/overlays'
>>>>>>> f79e31d (WIP.)
import { useTwitchEvent } from '~/hooks'
import { useChannel } from '~/hooks/use-channel'
import {
  getChannelInfo,
  NextApiResponseServerIO,
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

const Background = ({
  game
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
  const { data } = useChannel()
  const [category, setCategory] = useState('')
  const [timestamp, setTimestamp] = useState('')
  const [title, setTitle] = useState('')

  useEffect(() => {
    setCategory(game)
  }, [])

  useTwitchEvent((twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key } as TwitchStatusEvent

    switch (event.type) {
      case 'channel.update':
        logger.info('channel.update', event)
        const { category_name, title } = event.event
        logger.info(`the category is ${category_name}`)
        setCategory(category_name)
        setTitle(title)
        break
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
        <div className="grid grid-cols-[288px_1600px] h-full">
          <Sidebar />
          <div className="bg-black/90 rounded-r-lg" />
        </div>
      </Window>
      <Wallpaper category={data?.game} />
    </div>
  )
}

export const getServerSideProps: GetServerSideProps = async context => {
  const channel = await getChannelInfo(context.res as NextApiResponseServerIO)
  return {
    props: {
      game: channel?.gameName,
      debug: context.query.debug === 'true'
    }
  }
}

export default Background

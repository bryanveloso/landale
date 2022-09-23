import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
import { useEffect, useState } from 'react'
import { ApiClient } from '@twurple/api'

import { MenuBar, VerticalCamera, Wallpaper } from '~/components/overlays'
import {
  Controls,
  TitleBar,
  Sidebar,
  Window
} from '~/components/overlays/window'
import { useTwitchEvent } from '~/hooks'
import {
  getStreamInfo,
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
  stream
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
  const [category, setCategory] = useState('')
  const [timestamp, setTimestamp] = useState('')
  const [title, setTitle] = useState('')

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
    <div>
      <MenuBar />
      <Window>
        <div className="absolute w-full h-full rounded-lg ring-1 ring-offset-0 ring-inset ring-white/10 z-50" />
        <Controls />
        <TitleBar category={category} />
        <div className="grid grid-cols-[288px_1600px] h-full">
          <Sidebar />
        </div>
      </Window>
      <Wallpaper category={category} />
    </div>
  )
}

const getServerSideProps: GetServerSideProps = async context => {
  const rawStream = await getStreamInfo(context.res as NextApiResponseServerIO)
  const stream = JSON.parse(JSON.stringify(rawStream))

  return {
    props: { stream }
  }
}

export default Background

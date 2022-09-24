import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
import { ApiClient } from '@twurple/api'
import { ClientCredentialsAuthProvider } from '@twurple/auth'
import { useEffect, useState } from 'react'

import { Dock, MenuBar, VerticalCamera, Wallpaper } from '~/components/overlays'
import {
  Controls,
  TitleBar,
  Sidebar,
  Window
} from '~/components/overlays/window'
import { useTwitchEvent } from '~/hooks'
import {
  getChannelInfo,
  getStreamInfo,
  NextApiResponseServerIO,
  TwitchChannelUpdateEvent,
  TwitchEvent,
  TwitchStreamOfflineEvent,
  TwitchStreamOnlineEvent
} from '~/lib'
import { logger } from '~/logger'
import gameList from '~/lib/games'

type TwitchStatusEvent =
  | TwitchChannelUpdateEvent
  | TwitchStreamOfflineEvent
  | TwitchStreamOnlineEvent

const Background = ({
  game
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
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
        <TitleBar category={category} />
        <div className="grid grid-cols-[288px_1600px] h-full">
          <Sidebar />
        </div>
      </Window>
      <Wallpaper category={category} />
    </div>
  )
}

export const getServerSideProps: GetServerSideProps = async context => {
  const { TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET, TWITCH_USER_ID } = process.env

  try {
    const authProvider = new ClientCredentialsAuthProvider(
      TWITCH_CLIENT_ID!,
      TWITCH_CLIENT_SECRET!
    )
    const apiClient = new ApiClient({ authProvider })
    const channel = await apiClient.channels.getChannelInfoById(TWITCH_USER_ID!)

    return {
      props: { game: channel?.gameName }
    }
  } catch (error) {
    console.error(error)
    return { props: {} }
  }
}

export default Background

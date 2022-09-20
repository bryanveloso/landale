import hash from 'object-hash'
import { useState } from 'react'

import { MenuBar } from 'components/overlays/menubar'
import { Wallpaper } from 'components/overlays/wallpaper'
import { Window } from 'components/overlays/window'
import { useTwitchEvent } from 'hooks/use-twitch-event'
import {
  TwitchChannelUpdateEvent,
  TwitchEvent,
  TwitchStreamOfflineEvent,
  TwitchStreamOnlineEvent
} from 'lib'
import { logger } from 'logger'

type TwitchStatusEvent =
  | TwitchChannelUpdateEvent
  | TwitchStreamOfflineEvent
  | TwitchStreamOnlineEvent

const Background = () => {
  const [category, setCategory] = useState('')
  const [timestamp, setTimestamp] = useState('')
  const [title, setTitle] = useState('')

  const handleTwitchEvent = (twitchEvent: TwitchEvent) => {
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
  }

  useTwitchEvent(handleTwitchEvent)

  return (
    <>
      <MenuBar />
      <Window category={category} />
      <Wallpaper />
    </>
  )
}

export default Background

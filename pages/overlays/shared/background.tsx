import hash from 'object-hash'
import { useState } from 'react'

import { MenuBar } from 'components/overlays/menubar'
import { Wallpaper } from 'components/overlays/wallpaper'
import { Window } from 'components/overlays/window'
import { useTwitchEvent } from 'hooks/use-twitch-event'
import { TwitchEvent } from 'lib'
import { logger } from 'logger'

const Background = () => {
  const [category, setCategory] = useState<string>()

  const handleTwitchEvent = (twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key }

    if (event.type === 'channel.update') {
      setCategory(event.event.category_name)
      logger.info(event)
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

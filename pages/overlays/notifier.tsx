import hash from 'object-hash'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'

import { NotifiableTwitchEvent } from 'components/notification'
import { useSocket } from 'hooks'
import { useEvent } from 'hooks/use-event'
import { useQueue } from 'hooks/use-queue'
import { useTwitchEvent } from 'hooks/use-twitch-event'
import { TwitchEvent } from 'lib/twitch.controller'
import { useState } from 'react'

const MAX_NOTIFICATIONS = 2
const NOTIFICATION_DURATION = 3
const NOTIFICATION_PANEL_HEIGHT = MAX_NOTIFICATIONS * 100 + 65

export default function Notifier({}: InferGetServerSidePropsType<
  typeof getServerSideProps
>) {
  const [transitioning, setTransitioning] = useState(false)

  const [_, setNotifications, notifications, previous] = useQueue({
    count: MAX_NOTIFICATIONS,
    timeout: NOTIFICATION_DURATION * 1000
  })

  const notificationsWithPrevious = [previous, ...(notifications || [])].filter(
    notification => !!notification
  ) as NotifiableTwitchEvent[]

  const handleTwitchEvent = (twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key }

    if (event.type !== 'channel.update') {
      setNotifications(n => [...n, event])
    }
  }

  useTwitchEvent(handleTwitchEvent)

  const { socket } = useSocket()
  useEvent<boolean>(socket, 'transitioning', value => setTransitioning(value))

  return <div className="relative h-[1080px] w-[1920px]"></div>
}

export const getServerSideProps: GetServerSideProps = async context => {
  return {
    props: {}
  }
}

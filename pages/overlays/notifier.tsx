import hash from 'object-hash'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'

import { useQueue } from 'hooks/use-queue'
import { TwitchEvent } from 'lib/twitch.controller'

const MAX_NOTIFICATIONS = 2
const NOTIFICATION_DURATION = 3
const NOTIFICATION_PANEL_HEIGHT = MAX_NOTIFICATIONS * 100 + 65

export default function Notifier({}: InferGetServerSidePropsType<
  typeof getServerSideProps
>) {
  const [_, setNotifications, notifications, previous] = useQueue({
    count: MAX_NOTIFICATIONS,
    timeout: NOTIFICATION_DURATION * 1000
  })

  const notificationsWithPrevious = [previous, ...(notifications || [])].filter(
    notification => !!notification
  )

  const handleTwitchEvent = (twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key }

    if (event.type !== 'channel.update') {
      setNotifications(n => [...n, event])
    }
  }
}

export const getServerSideProps: GetServerSideProps = async context => {
  return {
    props: {}
  }
}

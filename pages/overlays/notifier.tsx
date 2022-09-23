import { motion, AnimatePresence } from 'framer-motion'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
import { useState } from 'react'

import {
  NotifiableTwitchEvent,
  Notification,
  SubscriptionNotification
} from 'components/notification'
import { useSocket } from 'hooks'
import { useEvent } from 'hooks/use-event'
import { useQueue } from 'hooks/use-queue'
import { useTwitchEvent } from 'hooks/use-twitch-event'
import { TwitchEvent } from 'lib/twitch.controller'

const MAX_NOTIFICATIONS = 2
const NOTIFICATION_DURATION = 3
const NOTIFICATION_PANEL_HEIGHT = MAX_NOTIFICATIONS * 100 + 65

export interface NotifierSSRProps {
  debug: boolean
}

export default function Notifier({
  debug
}: InferGetServerSidePropsType<typeof getServerSideProps>): JSX.Element {
  const [transitioning, setTransitioning] = useState(false)

  const [_, setNotifications, notifications, previous] = useQueue({
    count: MAX_NOTIFICATIONS,
    timeout: NOTIFICATION_DURATION * 1000
  })

  const notificationsWithPrevious = [previous, ...(notifications || [])].filter(
    notification => !!notification
  ) as NotifiableTwitchEvent[]

  useTwitchEvent((twitchEvent: TwitchEvent) => {
    const key = hash(twitchEvent)
    const event = { ...twitchEvent, key }

    if (event.type !== 'channel.update') {
      setNotifications(n => [...n, event])
    }
  })

  const { socket } = useSocket()
  useEvent<boolean>(socket, 'transitioning', value => setTransitioning(value))

  return (
    <div className="relative h-[1080px] w-[1920px]">
      <ul className="absolute top-20 right-8 z-50 h-52 w-96">
        <AnimatePresence initial={false}>
          {notificationsWithPrevious?.map(notification => (
            <motion.li
              key={notification.key}
              layout
              initial={{ opacity: 0.33, y: -50 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.5,
                type: 'spring',
                damping: 25,
                stiffness: 300,
                mass: 0.5
              }}
              exit={{
                opacity: 0,
                x: 200,
                transition: { duration: 0.5 }
              }}
            >
              <Notification notification={notification} className="list-none" />
            </motion.li>
          ))}
        </AnimatePresence>
      </ul>
    </div>
  )
}

export const getServerSideProps: GetServerSideProps<
  NotifierSSRProps
> = async context => {
  return {
    props: {
      debug: context.query.debug === 'true'
    }
  }
}

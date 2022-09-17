import { FC } from 'react'

import { TwitchChannelSubscriptionEvent } from '../lib'

export interface SubscriptionNotificationProps {
  event: TwitchChannelSubscriptionEvent
}
export const SubscriptionNotification: FC<SubscriptionNotificationProps> = ({
  event
}) => {
  return <div></div>
}

export type NotifiableTwitchEvent = TwitchChannelSubscriptionEvent

export interface NotificationProps extends React.ComponentProps<'div'> {
  notification: NotifiableTwitchEvent
}

export const Notification: FC<NotificationProps> = ({
  notification,
  ...props
}) => {
  switch (notification.type) {
    case 'channel.subscribe':
      return <SubscriptionNotification event={notification} {...props} />

    default:
      return null
  }
}

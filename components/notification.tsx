import React, { ComponentProps, FC, PropsWithChildren } from 'react'

import {
  TwitchChannelCheerEvent,
  TwitchChannelFollowEvent,
  TwitchChannelSubscriptionEvent,
  TwitchEvent
} from 'lib'

export interface NotificationContainerProps
  extends PropsWithChildren<ComponentProps<'div'>> {}

export const NotificationContainer: FC<NotificationContainerProps> = ({
  children,
  className = '',
  ...props
}) => {
  return (
    <div
      className={`max-w-md w-full bg-slate-900 shadow-lg rounded-lg flex ring-1 ring-white ring-opacity-10`}
    >
      <div className="flex-1 w-0 p-4">
        <div className="flex items-start">{children}</div>
      </div>
    </div>
  )
}

export interface SubscriptionNotificationProps extends ComponentProps<'div'> {
  event: TwitchChannelSubscriptionEvent
}
export const SubscriptionNotification: FC<SubscriptionNotificationProps> = ({
  event,
  className = '',
  ...props
}) => {
  return (
    <NotificationContainer>
      {/* <div className={className} {...props}> */}
      <div className="flex-shrink-0 pt-0.5"></div>
      <div className="ml-3 flex-1">
        Subscription from {event.event.user_name}
      </div>
    </NotificationContainer>
  )
}

export type NotifiableTwitchEvent =
  | TwitchChannelSubscriptionEvent
  | TwitchChannelCheerEvent
  | TwitchChannelFollowEvent

export interface NotificationProps extends ComponentProps<'div'> {
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

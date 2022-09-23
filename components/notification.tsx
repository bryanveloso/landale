import React, { ComponentProps, FC, PropsWithChildren } from 'react'

import {
  TwitchChannelCheerEvent,
  TwitchChannelSubscriptionEvent,
  TwitchChannelSubscriptionGiftEvent
} from 'lib'

export const getTier = (plan: string) =>
  ({ Prime: 'Prime', 1000: 'Tier 1', 2000: 'Tier 2', 3000: 'Tier 3' }[plan])

export interface NotificationContainerProps
  extends PropsWithChildren<ComponentProps<'div'>> {}

export const NotificationContainer: FC<NotificationContainerProps> = ({
  children,
  className = '',
  ...props
}) => {
  return (
    <div
      className={`max-w-md w-full bg-slate-900 shadow-lg rounded-lg flex ring-1 ring-white ring-opacity-10 mb-2`}
    >
      <div className="w-[420px] z-50 rounded-lg shadow-lg shadow-black/50 bg-[#2F3036] p-4 ring-2 ring-offset-0 ring-inset ring-white/20">
        <div className="flex gap-3 items-center">{children}</div>
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
    <NotificationContainer className={className} {...props}>
      <div className="w-14 h-14"></div>
      <div className="text-sm text-[#EAEAEB]">
        <strong className="font-bold">Subscription</strong>
        <div>
          {`${event.event.user_name} subscribed at ${getTier(
            event.event.tier
          )}`}
        </div>
      </div>
    </NotificationContainer>
  )
}

export interface SubscriptionGiftNotificationProps
  extends ComponentProps<'div'> {
  event: TwitchChannelSubscriptionGiftEvent
}
export const SubscriptionGiftNotification: FC<
  SubscriptionGiftNotificationProps
> = ({ event, className = '', ...props }) => {
  const user = event.event.is_anonymous ? 'Anonymous' : event.event.user_name

  return (
    <NotificationContainer className={className} {...props}>
      <div className="w-14 h-14"></div>
      <div className="text-sm text-[#EAEAEB]">
        <strong className="font-bold">Subscription Gift</strong>
        <div>
          {`${user} gifted ${event.event.cumulative_total} tier ${getTier(
            event.event.tier
          )} subscriptions`}
        </div>
      </div>
    </NotificationContainer>
  )
}

export type NotifiableTwitchEvent =
  | TwitchChannelCheerEvent
  | TwitchChannelSubscriptionEvent
  | TwitchChannelSubscriptionGiftEvent

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
    case 'channel.subscription.gift':
      return <SubscriptionGiftNotification event={notification} {...props} />

    default:
      return null
  }
}

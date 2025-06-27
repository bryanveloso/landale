import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { trpcClient } from '@/lib/trpc'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(widget)/alerts')({
  component: AlertsOverlay
})

interface Alert {
  id: string
  type: 'follow' | 'subscription' | 'gift' | 'resub' | 'redemption'
  message: string
  timestamp: number
}

function AlertsOverlay() {
  const [alerts, setAlerts] = useState<Alert[]>([])
  const [currentAlert, setCurrentAlert] = useState<Alert | null>(null)

  // Subscribe to Twitch events
  useEffect(() => {
    const subscriptions = [
      trpcClient.twitch.onFollow.subscribe(undefined, {
        onData: (data) => {
          const alert: Alert = {
            id: `follow-${Date.now().toString()}`,
            type: 'follow',
            message: `${data.userDisplayName ?? 'Someone'} just followed!`,
            timestamp: Date.now()
          }
          setAlerts((prev) => [...prev, alert])
        }
      }),

      trpcClient.twitch.onSubscription.subscribe(undefined, {
        onData: (data) => {
          const alert: Alert = {
            id: `sub-${Date.now().toString()}`,
            type: 'subscription',
            message: `${data.userDisplayName ?? 'Someone'} just subscribed${data.tier ? ` (Tier ${data.tier})` : ''}!`,
            timestamp: Date.now()
          }
          setAlerts((prev) => [...prev, alert])
        }
      }),

      trpcClient.twitch.onSubscriptionGift.subscribe(undefined, {
        onData: (data) => {
          const alert: Alert = {
            id: `gift-${Date.now().toString()}`,
            type: 'gift',
            message: data.isAnonymous
              ? `An anonymous user gifted ${(data.amount ?? 1).toString()} sub${(data.amount ?? 1) > 1 ? 's' : ''}!`
              : `${data.gifterDisplayName ?? 'Someone'} gifted ${(data.amount ?? 1).toString()} sub${(data.amount ?? 1) > 1 ? 's' : ''}!`,
            timestamp: Date.now()
          }
          setAlerts((prev) => [...prev, alert])
        }
      }),

      trpcClient.twitch.onSubscriptionMessage.subscribe(undefined, {
        onData: (data) => {
          const alert: Alert = {
            id: `resub-${Date.now().toString()}`,
            type: 'resub',
            message: `${data.userDisplayName ?? 'Someone'} resubscribed for ${(data.cumulativeMonths ?? 0).toString()} months!${data.messageText ? ` "${data.messageText}"` : ''}`,
            timestamp: Date.now()
          }
          setAlerts((prev) => [...prev, alert])
        }
      }),

      trpcClient.twitch.onRedemption.subscribe(undefined, {
        onData: (data) => {
          const alert: Alert = {
            id: `redemption-${Date.now().toString()}`,
            type: 'redemption',
            message: `${data.userDisplayName ?? 'Someone'} redeemed ${data.rewardTitle ?? 'a reward'}${data.input ? `: ${data.input}` : ''}`,
            timestamp: Date.now()
          }
          setAlerts((prev) => [...prev, alert])
        }
      })
    ]

    return () => {
      subscriptions.forEach((sub) => {
        sub.unsubscribe()
      })
    }
  }, [])

  // Process alert queue
  useEffect(() => {
    if (!currentAlert && alerts.length > 0) {
      setCurrentAlert(alerts[0] || null)
      setAlerts((prev) => prev.slice(1))
    }
  }, [alerts, currentAlert])

  // Auto-hide alerts after 5 seconds
  useEffect(() => {
    if (currentAlert) {
      const timer = setTimeout(() => {
        setCurrentAlert(null)
      }, 5000)
      return () => {
        clearTimeout(timer)
      }
    }
    return undefined
  }, [currentAlert])

  return (
    <ErrorBoundary>
      <div className="pointer-events-none fixed inset-0">
        <AnimatePresence>
          {currentAlert && (
            <motion.div
              key={currentAlert.id}
              initial={{ opacity: 0, y: -50, scale: 0.9 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 50, scale: 0.9 }}
              transition={{ duration: 0.3, type: 'spring', stiffness: 200 }}
              className="pointer-events-auto absolute top-8 left-1/2 -translate-x-1/2">
              <div
                className={`rounded-lg px-8 py-4 shadow-2xl backdrop-blur-md ${currentAlert.type === 'follow' ? 'bg-purple-500/90' : ''} ${currentAlert.type === 'subscription' ? 'bg-blue-500/90' : ''} ${currentAlert.type === 'gift' ? 'bg-green-500/90' : ''} ${currentAlert.type === 'resub' ? 'bg-indigo-500/90' : ''} ${currentAlert.type === 'redemption' ? 'bg-yellow-500/90' : ''} `}>
                <p className="text-center text-xl font-bold text-white">{currentAlert.message}</p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Alert queue indicator */}
        {alerts.length > 0 && (
          <div className="absolute top-4 right-4 rounded-full bg-white/10 px-3 py-1 backdrop-blur-sm">
            <p className="text-sm text-white">
              {alerts.length} alert{alerts.length !== 1 ? 's' : ''} queued
            </p>
          </div>
        )}
      </div>
    </ErrorBoundary>
  )
}

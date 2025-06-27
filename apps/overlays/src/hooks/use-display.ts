import { useEffect, useState } from 'react'
import { trpcClient } from '@/lib/trpc'
import type { Display } from '@landale/shared'
import type { UseDisplayOptions, UseDisplayReturn } from '@landale/shared'
import { wsLogger } from '@/lib/logger'

export function useDisplay<T = unknown>(displayId: string, options?: UseDisplayOptions): UseDisplayReturn<T> {
  const [display, setDisplay] = useState<Display<T> | null>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    const subscription = trpcClient.displays.subscribe.subscribe(
      { id: displayId },
      {
        onData: (data: Display<T>) => {
          setDisplay(data)
          setIsConnected(true)
          options?.onData?.(data.data)
        },
        onError: (error: Error) => {
          wsLogger.error('Display subscription error', {
            error,
            metadata: { displayId }
          })
          setIsConnected(false)
          options?.onError?.(error)
        }
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [displayId, options])

  const update = async (data: Partial<T>) => {
    await trpcClient.displays.update.mutate({ id: displayId, data })
  }

  const setVisibility = async (isVisible: boolean) => {
    await trpcClient.displays.setVisibility.mutate({ id: displayId, isVisible })
  }

  const clear = async () => {
    await trpcClient.displays.clear.mutate({ id: displayId })
  }

  return {
    data: display?.data ?? null,
    display,
    isConnected,
    isVisible: display?.isVisible ?? false,
    update,
    setVisibility,
    clear
  }
}

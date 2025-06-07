import { useEffect, useState } from 'react'
import { trpcClient } from '@/lib/trpc'
import type { Display } from '@landale/shared'
import type { UseDisplayOptions, UseDisplayReturn } from '@landale/shared'

export function useDisplay<T = any>(
  displayId: string,
  options?: UseDisplayOptions
): UseDisplayReturn<T> {
  const [display, setDisplay] = useState<Display<T> | null>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    const subscription = trpcClient.displays.subscribe.subscribe(
      { id: displayId },
      {
        onData: (data) => {
          setDisplay(data as Display<T>)
          setIsConnected(true)
          options?.onData?.(data.data)
        },
        onError: (error) => {
          console.error(`[useDisplay] Error for ${displayId}:`, error)
          setIsConnected(false)
          options?.onError?.(error)
        }
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [displayId])

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
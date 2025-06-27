import { useSubscription } from './use-subscription'
import { trpcClient } from '@/lib/trpc-client'
import type { Display } from '@landale/shared'
import type { UseDisplayOptions, UseDisplayReturn } from '@landale/shared'

export function useDisplay<T = unknown>(displayId: string, options?: UseDisplayOptions): UseDisplayReturn<T> {
  const { data: display, isConnected } = useSubscription<Display<T>>(
    'displays.subscribe',
    { id: displayId },
    {
      onData: (data) => {
        options?.onData?.(data.data)
      },
      onError: options?.onError
    }
  )

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

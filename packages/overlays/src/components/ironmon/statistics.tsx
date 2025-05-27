import { useQueryClient } from '@tanstack/react-query'
import { type FC, memo, useEffect, useState } from 'react'
import { type IronmonEvent } from '@landale/server/events/ironmon/types'

export const Statistics: FC = memo(() => {
  const queryClient = useQueryClient()
  const [checkpointData, setCheckpointData] = useState<IronmonEvent['checkpoint']['metadata'] | undefined>()

  // Subscribe to query cache updates
  useEffect(() => {
    // Get initial data
    setCheckpointData(queryClient.getQueryData(['ironmon', 'checkpoint']))

    // Subscribe to updates
    const unsubscribe = queryClient.getQueryCache().subscribe((event) => {
      if (event?.query?.queryKey?.[0] === 'ironmon' && event?.query?.queryKey?.[1] === 'checkpoint') {
        setCheckpointData(queryClient.getQueryData(['ironmon', 'checkpoint']))
      }
    })

    return () => unsubscribe()
  }, [queryClient])

  return (
    <div className="flex flex-col p-4 text-white">
      <div className="flex flex-1 justify-between">
        <div className="text-shark-500 font-bold">CHECKPOINT CLEAR RATE</div>
        <div className="text-xl font-bold tabular-nums">{checkpointData?.next?.clearRate ?? 0}%</div>
      </div>
      <div className="flex justify-between">
        <div className="text-shark-500 font-bold">LAST CLEARED</div>
        <div className="text-xl font-bold tabular-nums">#{checkpointData?.next?.lastCleared ?? 0}</div>
      </div>
    </div>
  )
})

Statistics.displayName = 'Statistics'

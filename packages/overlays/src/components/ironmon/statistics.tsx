import { useQuery } from '@tanstack/react-query'
import { FC } from 'react'

import { type CheckpointMessage } from '@/lib/services/ironmon'

export const Statistics: FC = () => {
  const query = useQuery<CheckpointMessage['metadata']>({
    queryKey: ['ironmon', 'checkpoint'],

    // Because we recieve this data via a websocket, we don't want to refetch it.
    gcTime: Infinity,
    staleTime: Infinity,
    refetchOnMount: false,
    refetchOnReconnect: false
  })

  return (
    <div className="flex flex-col p-4 text-white">
      <div className="flex flex-1 justify-between">
        <div className="text-shark-500 font-bold">CHECKPOINT CLEAR RATE</div>
        <div className="text-xl font-bold tabular-nums">{query.data?.next.clearRate}%</div>
      </div>
      <div className="flex justify-between">
        <div className="text-shark-500 font-bold">LAST CLEARED</div>
        <div className="text-xl font-bold tabular-nums">#{query.data?.next.lastCleared}</div>
      </div>
    </div>
  )
}

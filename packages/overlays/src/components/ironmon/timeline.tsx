import { CheckpointMessage } from '@/lib/services/ironmon'
import { useQuery } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import { type FC, Fragment, useEffect, useState } from 'react'

export const Timeline: FC<{ totalCheckpoints?: number }> = ({ totalCheckpoints = 24 }) => {
  const [currentCheckpoint, setCurrentCheckpoint] = useState<number>(1)
  const query = useQuery<CheckpointMessage['metadata']>({
    queryKey: ['ironmon', 'checkpoint'],
    placeholderData: { id: 1, name: 'LAB' },

    // Because we recieve this data via a websocket, we don't want to refetch it.
    gcTime: Infinity,
    staleTime: Infinity,
    refetchOnMount: false,
    refetchOnReconnect: false
  })

  const checkpoints = Array.from({ length: totalCheckpoints }, (_, i) => i + 1)

  useEffect(() => {
    if (!query.data) return

    console.log(query.data?.id, query.data?.name)
    setCurrentCheckpoint(query.data?.id || 1)
  }, [query.data])

  return (
    <div className="flex items-center">
      {checkpoints.map((checkpoint, index) => (
        <Fragment key={checkpoint}>
          {index > 0 && (
            <motion.div
              className="bg-shark-400 -m-0.5 h-1 w-3"
              initial={false}
              animate={{ width: currentCheckpoint > index ? 24 : 24 }}
              transition={{ duration: 0.5 }}
            />
          )}
          <motion.div
            className="border-shark-400 bg-avablue h-4 w-4 shrink-0 rounded-full border-4"
            initial={{ scale: 0.8 }}
            animate={{
              opacity: currentCheckpoint >= checkpoint ? 1 : 1,
              scale: currentCheckpoint >= checkpoint ? 1.2 : 1
            }}
            style={{
              backgroundColor: currentCheckpoint >= checkpoint ? 'var(--color-white)' : 'var(--color-shark-400)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
          />
        </Fragment>
      ))}
    </div>
  )
}

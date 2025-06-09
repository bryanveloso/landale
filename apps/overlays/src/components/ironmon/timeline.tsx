import { type IronmonEvent } from '@landale/server'
import { useQueryClient } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import { type FC, Fragment, useEffect, useState } from 'react'

export const Timeline: FC<{ totalCheckpoints?: number }> = ({ totalCheckpoints = 24 }) => {
  const [currentCheckpoint, setCurrentCheckpoint] = useState<number>(1)
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

    return () => {
      unsubscribe()
    }
  }, [queryClient])

  const checkpoints = Array.from({ length: totalCheckpoints }, (_, i) => i + 1)

  useEffect(() => {
    if (!checkpointData) return

    console.log(checkpointData?.id, checkpointData?.name)
    setCurrentCheckpoint(checkpointData?.id || 1)
  }, [checkpointData])

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

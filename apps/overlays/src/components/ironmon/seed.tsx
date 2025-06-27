import { useEffect, useState, type FC, memo } from 'react'
import { useQueryClient } from '@tanstack/react-query'

import { type IronmonEvent } from '@landale/server'
import { animate, motion, useMotionValue, useTransform } from 'framer-motion'

export const Seed: FC = memo(() => {
  const queryClient = useQueryClient()
  const [seedData, setSeedData] = useState<IronmonEvent['seed']['metadata'] | undefined>()

  // Subscribe to query cache updates
  useEffect(() => {
    // Get initial data
    setSeedData(queryClient.getQueryData(['ironmon', 'seed']))

    // Subscribe to updates
    const unsubscribe = queryClient.getQueryCache().subscribe((event) => {
      if (
        event.query.queryKey &&
        (event.query.queryKey as string[])[0] === 'ironmon' &&
        (event.query.queryKey as string[])[1] === 'seed'
      ) {
        setSeedData(queryClient.getQueryData(['ironmon', 'seed']))
      }
    })

    return () => {
      unsubscribe()
    }
  }, [queryClient])

  const value = useMotionValue(0)
  const count = useTransform(value, (v) => Math.round(v))

  useEffect(() => {
    const controls = animate(value, seedData?.count || 0, { duration: 2 })
    return controls.stop
  }, [value, seedData?.count])

  return <motion.span className="tabular-nums">{count}</motion.span>
})

Seed.displayName = 'Seed'

import { useEffect, type FC } from 'react'
import { useQuery } from '@tanstack/react-query'

import { type SeedMessage } from '@/lib/services/ironmon'
import { animate, motion, useMotionValue, useTransform } from 'framer-motion'

export const Seed: FC = () => {
  const query = useQuery<SeedMessage['metadata']>({
    queryKey: ['ironmon', 'seed'],
    placeholderData: { count: 0 },

    // Because we recieve this data via a websocket, we don't want to refetch it.
    gcTime: Infinity,
    staleTime: Infinity,
    refetchOnMount: false,
    refetchOnReconnect: false
  })

  const value = useMotionValue(0)
  const count = useTransform(value, (v) => Math.round(v))

  useEffect(() => {
    const controls = animate(value, query.data?.count || 0, { duration: 2 })
    return controls.stop
  }, [value, query.data?.count])

  return <motion.span className="tabular-nums">{count}</motion.span>
}

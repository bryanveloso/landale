'use client'

import {
  AnimatePresence,
  motion,
  useWillChange,
  type Variants,
} from 'framer-motion'
import type {
  RainwaveEvent,
  RainwaveEventSong,
  RequestLine,
  AlbumDiff,
  User,
  AllStationsInfo,
} from 'rainwave-websocket-sdk'
import type { ApiInfo } from 'rainwave-websocket-sdk/dist/types'
import {
  HydrationBoundary,
  QueryClient,
  dehydrate,
  useQuery,
} from '@tanstack/react-query'
import { useEffect, useState } from 'react'

import Icon from '@/components/icons'

import { getRainwave, type RainwaveResponse } from './rainwave'

const container = {
  hidden: {
    opacity: 0,
    width: 0,
    transition: {
      when: 'afterChildren',
    },
  },
  visible: {
    opacity: 1,
    width: 'fit-content',
    transition: {
      type: 'spring',
      bounce: 0,
      when: 'beforeChildren',
      staggerChildren: 0.1,
    },
  },
} as Variants

const item = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
} as Variants

export const RainwaveClient = () => {
  const { data, error, isSuccess } = useQuery({
    queryKey: ['rainwave'],
    queryFn: getRainwave,
    refetchInterval: 10 * 1000,
  })

  const [song, setSong] = useState<RainwaveEventSong>()
  const [isVisible, setIsVisible] = useState<boolean>()
  const willChange = useWillChange()

  useEffect(() => {
    setSong(data?.sched_current.songs[0])
    setIsVisible(data?.user.tuned_in)
  }, [data, isSuccess])

  return (
    song && (
      <AnimatePresence mode="wait">
        {isVisible && (
          <motion.div
            layout="position"
            initial="hidden"
            animate={isVisible ? 'visible' : 'hidden'}
            variants={container}
            exit="hidden"
            className="flex items-center rounded-md ring-inset ring-0 ring-white/50"
            style={{ willChange }}
          >
            <motion.div
              variants={item}
              className="flex items-center p-1.5 rounded-l-md px-3 font-semibold text-sm border-r border-white/50"
            >
              <Icon icon="music-line" size={24} />
              <span className="pl-2">!rainwave</span>
            </motion.div>
            <motion.div
              variants={item}
              className="text-white text-sm px-3 overflow-hidden"
            >
              <strong className="truncate">{song.title}</strong>
              <span className="text-white/50">
                {' by '}
                {Array.from(song.artists.values(), (v) => v.name).join(', ')}
              </span>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    )
  )
}

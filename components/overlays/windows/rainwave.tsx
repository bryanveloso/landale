import {
  AnimatePresence,
  motion,
  useWillChange,
  type Variants
} from 'framer-motion'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import { RainwaveEventSong } from 'rainwave-websocket-sdk'
import axios from 'redaxios'
import {
  type RainwaveEvent,
  type RequestLine,
  type AlbumDiff,
  type User,
  type AllStationsInfo
} from 'rainwave-websocket-sdk'
import { type ApiInfo } from 'rainwave-websocket-sdk/dist/types'
import { useQuery } from '@tanstack/react-query'
import { FC, useCallback, useEffect, useState } from 'react'
import Icon from '~/components/icons'

export interface RainwaveResponse {
  album_diff: AlbumDiff
  all_stations_info: AllStationsInfo
  api_info: ApiInfo
  request_line: RequestLine
  sched_current: RainwaveEvent
  sched_history: RainwaveEvent
  sched_next: RainwaveEvent
  user: User
}

const getRainwave = async (): Promise<RainwaveResponse> => {
  return await (
    await axios.get('https://rainwave.cc/api4/info', {
      params: { sid: 2, user_id: 53109, key: 'vYyXHv30AT' }
    })
  ).data
}

const container = {
  hidden: {
    opacity: 0,
    width: 0,
    transition: {
      when: 'afterChildren'
    }
  },
  visible: {
    opacity: 1,
    width: 'fit-content',
    transition: {
      type: 'spring',
      bounce: 0,
      when: 'beforeChildren',
      staggerChildren: 0.1
    }
  }
} as Variants

const item = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 }
} as Variants

export const Rainwave = ({
  initialData
}: {
  initialData: RainwaveResponse
}) => {
  const { status, data, error } = useQuery<RainwaveResponse, Error>(
    ['rainwave'],
    getRainwave,
    { initialData, refetchInterval: 1 * 1000 }
  )

  const [song, setSong] = useState<RainwaveEventSong>(
    data.sched_current.songs[0]
  )
  const [isVisible, setIsVisible] = useState<boolean>(data.user.tuned_in)
  const willChange = useWillChange()

  useEffect(() => {
    setSong(data.sched_current.songs[0])
    setIsVisible(data.user.tuned_in)
  }, [data])

  if (status === 'error') return <span>Error: {error?.message}</span>

  return (
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
              {Array.from(song.artists.values(), v => v.name).join(', ')}
            </span>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

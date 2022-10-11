import { AnimatePresence, motion } from 'framer-motion'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import hash from 'object-hash'
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
import { FC, useEffect, useState } from 'react'

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
  const [user, setUser] = useState<User>(data.user)
  const [isVisible, setIsVisible] = useState<boolean>(data.user.tuned_in)

  useEffect(() => {
    setUser(data.user)
    setSong(data.sched_current.songs[0])
  }, [data])

  if (status === 'error') return <span>Error: {error?.message}</span>

  return (
    <motion.div
      layout
      key={song.id}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ opacity: { duration: 0.2 } }}
      className="flex items-center max-w-fit"
    >
      <div
        className="flex justify-center rounded-sm w-6 h-6 aspect-square bg-cover bg-center ring-4 ring-black"
        style={{
          backgroundImage: `url(https://rainwave.cc${song.albums[0].art}_320.jpg)`
        }}
      />
      <motion.div
        key={hash(song.id)}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ opacity: { duration: 0.2 } }}
        className="pl-2 text-white text-sm"
      >
        {song.title}
        {Array.from(song.artists.values(), v => v.name).join(', ')}
      </motion.div>
      {/* <div className="text-xs font-bold">{'POWERED BY RAINWAVE.CC'}</div> */}
      {/* <div className="text-xs">
        <pre>{JSON.stringify(song, null, 2)}</pre>
      </div>
      <div className="text-xs">
        <pre>{JSON.stringify(user, null, 2)}</pre>
      </div> */}
    </motion.div>
  )
}

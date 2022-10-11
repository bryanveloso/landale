import { AnimatePresence, motion } from 'framer-motion'
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
import { useEffect, useState } from 'react'

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

const imageLoader = ({ src }: { src: string }) => {
  return ``
}

const NowPlaying = ({
  initialData
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
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
    <div
      key={song.id}
      className="relative flex items-center max-w-fit shadow-xl shadow-black bg-window rounded-md overflow-hidden"
    >
      <div className="absolute w-full h-full rounded-md ring-1 ring-offset-0 ring-inset ring-white/30 z-10" />
      <div
        className="flex justify-center rounded-l-md w-24 h-24 aspect-square bg-cover bg-center"
        style={{
          backgroundImage: `url(https://rainwave.cc${song.albums[0].art}_320.jpg)`
        }}
      />
      <div className="p-4 pl-6 pr-12 text-white">
        <div className="font-bold text-lg">{song.title}</div>
        <div>
          {song.artists.map(artist => (
            <span key={artist.id}>{artist.name}</span>
          ))}
        </div>
        {/* <div className="text-xs font-bold">{'POWERED BY RAINWAVE.CC'}</div> */}
      </div>
      {/* <div className="text-xs">
        <pre>{JSON.stringify(song, null, 2)}</pre>
      </div>
      <div className="text-xs">
        <pre>{JSON.stringify(user, null, 2)}</pre>
      </div> */}
    </div>
  )
}

export default NowPlaying

export const getServerSideProps: GetServerSideProps<{
  initialData: RainwaveResponse
}> = async () => {
  const initialData = await getRainwave()

  return {
    props: { initialData }
  }
}

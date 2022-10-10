import { Rainwave, RainwaveEventSong, Station } from 'rainwave-websocket-sdk'
import { useEffect, useRef, useState } from 'react'
import { useRainwave } from '~/hooks'

const apiKey = process.env.RAINWAVE_API_KEY!
const userIdString = process.env.RAINWAVE_USER_ID!

const MAX_DEBUG_MESSAGES = -10

const NowPlaying = () => {
  const { data } = useRainwave()

  // const [debug, setDebug] = useState<string[]>([])
  // const [error, setError] = useState('No errors.')
  // const [timestamp, setTimestamp] = useState<number>(0)
  // const [song, setSong] = useState<RainwaveEventSong>()

  // const init = async () => {
  //   const rainwave = new Rainwave({
  //     apiKey,
  //     userId: parseInt(userIdString, 10),
  //     sid: Station.ocremix,
  //     onSocketError: () => setError('Could not connect to Rainwave.'),
  //     debug: msg => {
  //       console.log('msg', msg)
  //     }
  //   })

  //   await rainwave.startWebSocketSync()

  //   rainwave.on('sched_current', current => {
  //     const currentSong = current.songs[0]
  //     console.log('song', currentSong)
  //     setSong(currentSong)
  //   })

  //   rainwave.on('ping', ({ timestamp }) => {
  //     console.log('timestamp', timestamp)
  //     setTimestamp(timestamp)
  //   })
  // }

  // init()

  // useEffect(() => {}, [])

  return <div>{JSON.stringify(data)}</div>
}

export default NowPlaying

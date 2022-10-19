import { useQuery } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import axios from 'redaxios'

import { Logomark } from '~/components/icons'
import { MenuBar, Wallpaper } from '~/components/overlays'
import {
  Controls,
  Sidebar,
  TitleBar,
  Window
} from '~/components/overlays/windows'
import {
  Rainwave,
  RainwaveResponse
} from '~/components/overlays/windows/rainwave'
import { Metadata } from '~/components/overlays/windows/titlebar-metadata'
import { useChannel, useHasMounted } from '~/hooks'

const Background = ({
  debug,
  rainwave
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
  const channel = useChannel()
  const hasMounted = useHasMounted()

  const { data } = useQuery(['kaizo'], async () => {
    return await (
      await axios.get('http://192.168.88.56:8008/stats/kaizo')
    ).data
  })

  return (
    <div className="relative w-[1920px] h-[1080px] bg-black">
      <MenuBar />
      <Window>
        <div className="absolute w-full h-full rounded-lg ring-1 ring-offset-0 ring-inset ring-white/10 z-50" />
        <Controls />
        <TitleBar>
          <Metadata key="metadata" channel={channel} />
          {/*  */}
          <div>
            <motion.div
              layout="position"
              className="grow flex items-center gap-3 pr-3 bg-black/40 rounded-md"
            >
              <div className="bg-black/40 p-2 rounded-l-md px-3 font-semibold text-sm text-white/50">
                Number of Attempts
              </div>
              <div className="font-bold">{data && data.attempts}</div>
            </motion.div>
          </div>
          {/*  */}
          {hasMounted && <Rainwave key="rainwave" initialData={rainwave} />}
        </TitleBar>
        <div className="grid grid-cols-[92px_196px_1600px] h-full">
          <div className="flex flex-col h-full bg-gradient-to-b from-black/50 to-black/30 shadow-sidebar-inset rounded-l-lg">
            <div className="grow"></div>
            <div className="py-6 text-white">
              <Logomark className="h-10 mx-auto opacity-10" />
            </div>
          </div>
          <Sidebar />
          <div className="bg-black/90 rounded-r-lg" />
        </div>
      </Window>
      <Wallpaper />
    </div>
  )
}

export const getServerSideProps: GetServerSideProps<{
  debug: boolean
  rainwave: RainwaveResponse
}> = async context => {
  const rainwave = await (
    await axios.get('https://rainwave.cc/api4/info', {
      params: { sid: 2, user_id: 53109, key: 'vYyXHv30AT' }
    })
  ).data

  return {
    props: {
      rainwave,
      debug: context.query.debug === 'true'
    }
  }
}

export default Background

import { AnimatePresence, motion } from 'framer-motion'
import { FC } from 'react'

import { VideoGamePC } from '~/components/icons'
import { useChannel } from '~/hooks/use-channel'

export const TitleBar: FC = () => {
  const channel = useChannel()

  return (
    <AnimatePresence mode="wait">
      <div className="absolute grid grid-cols-[288px_1600px] items-stretch w-full h-[52px] rounded-t-lg text-[#E5E5E5] z-50">
        <div className="flex items-center gap-3 px-5 justify-end"></div>
        <div className="flex items-center gap-3 px-5 shadow-titlebar-inset bg-titlebar rounded-tr-lg">
          <VideoGamePC className="w-6 h-6" />
          <motion.div
            key={channel?.data?.game}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ opacity: { duration: 0.2 } }}
            className="font-semibold"
          >
            {channel?.data?.game}
          </motion.div>
        </div>
      </div>
    </AnimatePresence>
  )
}

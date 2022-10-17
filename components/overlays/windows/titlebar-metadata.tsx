import { motion } from 'framer-motion'
import hash from 'object-hash'

import { ChannelResponse } from '~/hooks/use-channel'

export const Metadata = ({ channel }: { channel: ChannelResponse }) => {
  return (
    <motion.div
      layout="position"
      className="grow flex items-center gap-3 bg-black/40 rounded-md"
    >
      <div className="bg-black/40 p-2 rounded-l-md px-3 font-semibold text-sm text-white/50">
        Currently Playing
      </div>
      <motion.div
        key={hash(channel?.data)}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        className="font-bold"
      >
        {channel?.data?.game}
      </motion.div>
    </motion.div>
  )
}

import { AnimatePresence, motion } from 'framer-motion'
import hash from 'object-hash'
import { ChannelResponse, useChannel } from '~/hooks/use-channel'

export const Metadata = ({ channel }: { channel: ChannelResponse }) => {
  return (
    <motion.div
      key={hash(channel?.data)}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ opacity: { duration: 0.2 } }}
      className="grow text-center"
    >
      <strong>{channel?.data?.game}</strong>
    </motion.div>
  )
}

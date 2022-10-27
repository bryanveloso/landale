import { motion, AnimatePresence, Variants } from 'framer-motion'
import Image from 'next/image'
import { FC } from 'react'

import { useChannel } from '~/hooks'
import wallpapers from '~/lib/games'

const variants = {
  enter: {
    opacity: 0
  },
  visible: {
    opacity: 1
  },
  exit: {
    opacity: 0
  }
} as Variants

export const Wallpaper: FC = () => {
  const { data } = useChannel()
  const image = wallpapers.find(w => w.name === data?.game) ?? wallpapers[0]

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={image.name}
        variants={variants}
        initial="enter"
        animate="visible"
        exit="exit"
        transition={{ opacity: { duration: 0.5 } }}
        className="absolute top-0 w-[1920px] h-[1080px] overflow-hidden bg-black z-10"
      >
        <Image
          fill
          priority
          src={image?.wallpaper}
          alt="Wallpaper"
          style={{ objectFit: 'cover' }}
        />
      </motion.div>
    </AnimatePresence>
  )
}

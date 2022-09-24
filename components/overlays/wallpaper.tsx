import { motion, AnimatePresence, Variants } from 'framer-motion'
import Image from 'next/future/image'
import { FC } from 'react'

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

export interface WallpaperProps {
  category?: string
}

export const Wallpaper: FC<WallpaperProps> = ({ category }) => {
  const image = wallpapers.find(w => w.name === category) ?? wallpapers[0]

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={image.name}
        variants={variants}
        initial="enter"
        animate="visible"
        exit="exit"
        transition={{ opacity: { duration: 0.2 } }}
        className="absolute top-0 w-[1920px] h-[1080px] overflow-hidden bg-black z-10"
      >
        <Image
          fill
          priority
          src={image?.asset}
          alt="Wallpaper"
          style={{ objectFit: 'cover' }}
        />
      </motion.div>
    </AnimatePresence>
  )
}

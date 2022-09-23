import { motion, AnimatePresence, Variants } from 'framer-motion'
import Image from 'next/future/image'
import { FC, memo, useState } from 'react'

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

const wallpapers = [
  { game: 'Default', asset: '/wallpaper/default.png' },
  { game: 'Final Fantasy XIV Online', asset: '/wallpaper/ffxiv.png' },
  { game: 'Genshin Impact', asset: '/wallpaper/genshin.jpeg' }
]

export interface WallpaperProps {
  category?: string
}

export const Wallpaper: FC<WallpaperProps> = ({ category }) => {
  const image = wallpapers.find(w => w.game === category) ?? wallpapers[0]

  return (
    <AnimatePresence mode="wait" initial={false}>
      <div className="absolute top-0 w-[1920px] h-[1080px] overflow-hidden bg-black -z-50">
        <motion.div
          key={image.game}
          variants={variants}
          initial="enter"
          animate="visible"
          exit="exit"
          transition={{ opacity: { duration: 0.2 } }}
        >
          <Image
            fill
            priority
            src={image?.asset}
            alt="Wallpaper"
            style={{ objectFit: 'cover' }}
          />
        </motion.div>
      </div>
    </AnimatePresence>
  )
}

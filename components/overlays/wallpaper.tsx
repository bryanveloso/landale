import { motion, AnimatePresence } from 'framer-motion'
import { useState } from 'react'

const wallpapers = [
  { id: 0, name: 'xenoblade', asset: '/wallpaper/xenoblade.png' },
  { id: 1, name: 'endwalker', asset: 'endwalker.png' }
]

export const Wallpaper = () => {
  const [index, setIndex] = useState(0)

  return (
    <AnimatePresence>
      <div className="w-[1920px] h-[1080px] overflow-hidden">
        <motion.img src="/wallpaper/xenoblade.png" />
      </div>
    </AnimatePresence>
  )
}

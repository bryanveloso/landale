'use client'

import {
  AnimatePresence,
  motion,
  useWillChange,
  type Variants,
} from 'framer-motion'

import { useRainwave } from '@/hooks/use-rainwave'

const container = {
  hidden: {
    opacity: 0,
    width: 0,
    transition: {
      when: 'afterChildren',
    },
  },
  visible: {
    opacity: 1,
    width: 'fit-content',
    transition: {
      type: 'spring',
      bounce: 0,
      when: 'beforeChildren',
      staggerChildren: 0.1,
    },
  },
} as Variants

const item = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
} as Variants

export const RainwaveClient = () => {
  const { isTunedIn, song } = useRainwave()
  const willChange = useWillChange()

  return (
    song && (
      <AnimatePresence mode="wait">
        {isTunedIn && (
          <motion.div
            layout="position"
            initial="hidden"
            animate={isTunedIn ? 'visible' : 'hidden'}
            variants={container}
            exit="hidden"
            className="flex items-center rounded-md ring-inset ring-0 ring-white/50"
            style={{ willChange }}
          >
            <motion.div
              variants={item}
              className="text-white overflow-hidden mr-4"
            >
              <div>
                <strong className="truncate text-ellipsis text-lg">
                  {song.title}
                </strong>
              </div>
              <div>
                <span className="text-muted-green truncate w-24">
                  {song.albums[0].name}
                </span>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    )
  )
}

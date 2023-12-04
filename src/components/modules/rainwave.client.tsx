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
            className="flex items-center rounded-md ring-0 ring-inset ring-white/50"
            style={{ willChange }}
          >
            <motion.div
              variants={item}
              className="mr-4 overflow-hidden text-white"
            >
              <div className="truncate text-ellipsis text-xl">
                <strong>{song.title}</strong>
              </div>
              <div className="w-80 truncate text-ellipsis text-muted-green">
                <span>{song.albums[0].name}</span>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    )
  );
}

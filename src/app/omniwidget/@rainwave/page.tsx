'use client';

import { useRainwave } from '@/hooks/use-rainwave';
import {
  AnimatePresence,
  Variants,
  motion,
  useWillChange,
} from 'framer-motion';

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
    width: '384px',
    transition: {
      type: 'spring',
      bounce: 0,
      when: 'beforeChildren',
      staggerChildren: 0.2,
    },
  },
} as Variants;

const item = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
} as Variants;

const Page = () => {
  const { isTunedIn, song } = useRainwave();
  const willChange = useWillChange();

  return (
    <AnimatePresence mode="wait">
      {isTunedIn && (
        <motion.div
          className="relative flex h-full flex-col p-3 pl-4"
          initial="hidden"
          animate={isTunedIn ? 'visible' : 'hidden'}
          exit="hidden"
          variants={container}
          style={{ willChange }}
        >
          <div className="absolute right-0 top-0 h-36 w-12 bg-gradient-to-r from-transparent to-[#13141B]"></div>
          <motion.div className="flex-auto pt-1">
            <span className="rounded-sm px-2 py-1 text-sm text-muted-yellow ring-1 ring-muted-yellow/30">
              !rainwave
            </span>
            di
          </motion.div>
          <motion.div
            key={song?.title}
            className="max-w-sm truncate text-ellipsis"
            variants={item}
          >
            <span className="text-2xl font-extrabold text-white">
              {song?.title}
            </span>
          </motion.div>
          <motion.div
            key={song?.albums[0].name}
            className="max-w-sm truncate text-ellipsis"
            variants={item}
          >
            <span className="text-muted-green">{song?.albums[0].name}</span>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default Page;

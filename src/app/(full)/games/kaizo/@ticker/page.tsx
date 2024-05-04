'use client';

import { AnimatePresence, motion, useWillChange } from 'framer-motion';
import { useEffect, useState } from 'react';

import { useSocket } from '@/lib/socket.provider';

import { Seed } from './_components/seed';
import { Initializer } from './_components/initializer';
import { PB } from './_components/pb';

const Page = () => {
  const [checkpoiont, setCheckpoint] = useState<number>(0);
  const [initialized, setInitialized] = useState<boolean>(false);
  const {
    messages: { bizhawk },
  } = useSocket();

  useEffect(() => {
    bizhawk.filter(message => message.type === 'init').slice(-1).length &&
      setInitialized(true);
  }, [bizhawk]);

  return (
    <AnimatePresence mode="wait">
      <motion.div className="items-middle absolute bottom-0 flex h-16 w-[1499px] bg-shark-950 font-sans text-shark-50">
        <div className="flex w-full justify-between gap-12 px-12">
          {!initialized ? (
            <Initializer />
          ) : (
            <>
              <Seed />
              <PB />
            </>
          )}
        </div>
      </motion.div>
    </AnimatePresence>
  );
};

export default Page;

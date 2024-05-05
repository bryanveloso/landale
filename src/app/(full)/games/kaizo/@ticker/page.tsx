'use client';

import { AnimatePresence, motion, useWillChange } from 'framer-motion';
import { useEffect, useState } from 'react';

import { useSocket } from '@/lib/socket.provider';
import { type CheckpointMetadata } from '@/lib/services/landale/kaizo';

import { Checkpoint } from './_components/checkpoint';
import { Initializer } from './_components/initializer';
import { Seed } from './_components/seed';

const Page = () => {
  const [checkpointId, setCheckpointId] = useState<number>(0);
  const [checkpointName, setCheckpointName] = useState<string>('');
  const [initialized, setInitialized] = useState<boolean>(false);
  const {
    messages: { bizhawk },
  } = useSocket();

  useEffect(() => {
    bizhawk.filter(message => message.type === 'init').slice(-1).length &&
      setInitialized(true);

    bizhawk
      .filter(message => message.type === 'checkpoint')
      .slice(-1)
      .forEach(message => {
        setCheckpointId((message.metadata as CheckpointMetadata).number);
        setCheckpointName((message.metadata as CheckpointMetadata).name);
      });
    console.log(checkpointId, checkpointName);
  }, [bizhawk, checkpointId, checkpointName]);

  return (
    <motion.div className="items-middle absolute bottom-0 flex h-16 w-[1499px] bg-shark-950 font-sans text-shark-50">
      <div className="flex w-full gap-12 px-12">
        {!initialized ? (
          <Initializer />
        ) : (
          <>
            <Seed />
            <Checkpoint id={checkpointId} name={checkpointName} />
          </>
        )}
      </div>
    </motion.div>
  );
};

export default Page;

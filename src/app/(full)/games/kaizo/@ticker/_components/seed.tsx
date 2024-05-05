'use client';

import { animate, motion, useMotionValue, useTransform } from 'framer-motion';
import Image from 'next/image';
import { FC, useEffect, useState } from 'react';

import { useSocket } from '@/lib/socket.provider';
import { type SeedMetadata } from '@/lib/services/landale/kaizo';

import post from '~/public/games/kaizo/post.png';

export const Seed: FC = () => {
  const [seed, setSeed] = useState<number>(0);
  const {
    messages: { bizhawk },
  } = useSocket();

  useEffect(() => {
    bizhawk
      .filter(message => message.type === 'seed')
      .slice(-1)
      .forEach(message => setSeed((message.metadata as SeedMetadata).number));
  }, [bizhawk]);

  const count = useMotionValue(0);
  const number = useTransform(count, value => Math.round(value));

  useEffect(() => {
    const controls = animate(count, seed, { duration: 2 });
    return controls.stop;
  }, [count, seed]);

  return (
    <motion.div className="flex w-44 flex-none items-center" layout>
      <span className="relative rounded p-1 px-2 pl-12">
        <Image src={post} alt="Post" className="absolute -top-9 left-0" />
      </span>
      <span className="test bg-gradient-to-b from-main-avayellow to-main-avayellow/60 bg-clip-text pl-4 font-mono text-3xl font-black text-transparent">
        #<motion.span>{number}</motion.span>
      </span>
    </motion.div>
  );
};

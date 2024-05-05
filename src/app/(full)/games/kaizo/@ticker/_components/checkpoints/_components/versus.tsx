import { motion } from 'framer-motion';
import { Racing_Sans_One as RSO } from 'next/font/google';
import Image, { type StaticImageData } from 'next/image';
import { FC } from 'react';

import { cn } from '@/lib/utils';

import ava from '~/public/games/kaizo/ava.png';

interface VersusProps {
  name: string;
  image: StaticImageData;
}

const rso = RSO({ weight: '400', style: 'normal', subsets: ['latin'] });

export const Versus: FC<VersusProps> = ({ name, image }) => {
  return (
    <motion.div className="flex items-center justify-center">
      <div className="flex flex-row-reverse items-center">
        <div className="relative z-10 -ml-14 flex-none p-2">
          <Image src={ava} alt="" className="relative -top-2" priority />
        </div>
        <div className="relative rounded border-b border-shark-50/25 bg-black p-1 pl-3 pr-12 font-bold uppercase">
          Next Checkpoint
        </div>
      </div>
      <div className={cn(rso.className, 'flex text-3xl text-main-avayellow')}>
        VS
      </div>
      <div className="flex items-center">
        <div className="relative flex-none px-2 pl-3">
          <Image src={image} alt="" className="relative -top-2" priority />
        </div>
        <div className={cn(rso.className, 'text-3xl uppercase text-white')}>
          {name}
        </div>
      </div>
    </motion.div>
  );
};

import Image from 'next/image';
import { useEffect, useState } from 'react';

import {
  useKaizoAttemptCount,
  useKaizoAttempts,
} from '@/hooks/use-kaizo-attempts';
import {
  type LastHitResult,
  type PersonalBest,
  calculateCheckpointAverage,
  calculatePersonalBest,
  extractHeaders,
  findLastHitForCheckpoint,
  parseCSV,
} from '@/lib/services/landale/kaizo';

import ava from './ava.png';
import brock from './brock.png';
import oak from './oak.png';
import post from './post.png';

export const Ticker = () => {
  const { count, status: countStatus } = useKaizoAttemptCount();
  const { csv, status: csvStatus } = useKaizoAttempts();

  const [personalBest, setPersonalBest] = useState<PersonalBest>();
  const [labEscapeRate, setLabEscapeRate] = useState<string>();
  const [lastBrockEscape, setLastBrockEscape] = useState<LastHitResult>();

  useEffect(() => {
    if (csvStatus === 'success') {
      const attempts = parseCSV(csv);
      const headers = extractHeaders(csv);

      setPersonalBest(calculatePersonalBest(attempts, headers));
      setLabEscapeRate(calculateCheckpointAverage(attempts, 0));
      setLastBrockEscape(findLastHitForCheckpoint(attempts, 3));
    }
  }, [csv, csvStatus]);

  if (countStatus === 'pending' || csvStatus === 'pending') {
    return <div>Loading...</div>;
  }

  return (
    <div className="items-middle absolute bottom-0 flex h-16 w-[1499px] bg-shark-950 font-sans text-shark-50">
      <div className="flex w-full justify-between gap-12 px-12">
        <div className="flex items-center">
          <span className="relative rounded p-1 px-2 pl-12">
            <Image src={post} alt="Post" className="absolute -top-9 left-0" />
          </span>
          <span className="test bg-gradient-to-b from-main-avayellow to-main-avayellow/60 bg-clip-text pl-4 font-mono text-3xl font-black text-transparent">
            #{count}
          </span>
        </div>
        <div className="flex items-center">
          <span className="relative rounded bg-black p-1 px-2 pl-12">
            <Image src={ava} alt="Ava" className="absolute -left-4 -top-10" />
            <span className="text-muted-lightbluegrey">PERSONAL BEST</span>
          </span>
          <span className="pl-4 font-mono text-xl">
            #{personalBest?.id} <span className="opacity-50">|</span>{' '}
            {personalBest?.checkpoint}
          </span>
        </div>

        <div className="flex items-center">
          <span className="relative rounded bg-black p-1 px-2 pl-12">
            <Image src={oak} alt="Oak" className="absolute -left-4 -top-10" />
            <span className="text-muted-lightbluegrey">LAB ESCAPE RATE</span>
          </span>
          <span className="pl-4 font-mono text-xl">{labEscapeRate}%</span>
        </div>
        <div className="flex items-center">
          <span className="relative rounded bg-black p-1 px-2 pl-12">
            <Image
              src={brock}
              alt="Brock"
              className="absolute -left-4 -top-10"
            />
            <span className="text-muted-lightbluegrey">LAST BROCK ESCAPE</span>
          </span>
          <span className="pl-4 font-mono text-xl font-semibold">
            {lastBrockEscape?.distance} runs ago
          </span>
        </div>
      </div>
    </div>
  );
};

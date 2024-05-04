import Image from 'next/image';
import { FC, useEffect, useState } from 'react';

import { useKaizoAttempts } from '@/hooks/use-kaizo-attempts';
import {
  type PersonalBest,
  calculatePersonalBest,
  extractHeaders,
  parseCSV,
} from '@/lib/services/landale/kaizo';

import ava from '~/public/games/kaizo/ava.png';

export const PB: FC = () => {
  const { csv, status: csvStatus } = useKaizoAttempts();
  const [personalBest, setPersonalBest] = useState<PersonalBest>();

  useEffect(() => {
    if (csvStatus === 'success') {
      const attempts = parseCSV(csv);
      const headers = extractHeaders(csv);

      setPersonalBest(calculatePersonalBest(attempts, headers));
    }
  }, [csv, csvStatus]);

  return (
    <div className="flex items-center">
      <span className="relative rounded bg-black p-1 px-2 pl-12">
        <Image
          src={ava}
          alt="Ava"
          className="absolute -left-4 -top-10"
          priority
        />
        <span className="text-muted-lightbluegrey">PERSONAL BEST</span>
      </span>
      <span className="pl-4 font-mono text-xl">
        #{personalBest?.id} <span className="opacity-50">|</span>{' '}
        {personalBest?.checkpoint}
      </span>
    </div>
  );
};

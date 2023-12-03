'use client';

import { useRainwave } from '@/hooks/use-rainwave';
import Image from 'next/image';

export const Logomark = () => {
  const { isTunedIn } = useRainwave();

  return (
    <div className="flex items-center gap-2">
      <Image
        src="/avalonstar.png"
        width={36}
        height={36}
        alt="Avocadostar"
        priority
      />
      {isTunedIn && (
        <span className="rounded-sm px-2 py-0.5 text-sm text-muted-yellow ring-1 ring-muted-yellow/30">
          !rainwave
        </span>
      )}
    </div>
  );
};

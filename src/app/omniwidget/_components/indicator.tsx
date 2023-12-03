'use client';

import { FC, useEffect, useState } from 'react';

import { useSocket } from '@/hooks/use-socket';
import { cn } from '@/lib/utils';

export const Indicator: FC = () => {
  const [isMuted, setIsMuted] = useState(false);
  const { socket } = useSocket();

  useEffect(() => {
    socket?.on('obs:microphone', ({ muted }) => {
      setIsMuted(muted);
    });
  }, [socket]);

  return (
    <div
      className={cn(
        isMuted
          ? 'bg-red-600 shadow-[2px_0_12px_theme(colors.red.600)]'
          : 'bg-main-avagreen shadow-[2px_0_12px_theme(colors.main.avagreen)]',
        'absolute right-6 top-12 z-50 h-[148px] w-1 rounded-l-sm transition-colors'
      )}
    ></div>
  );
};

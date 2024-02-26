'use client';

import { FC, useCallback, useEffect, useState } from 'react';

import { useSocket } from '@/lib/socket.provider';
import { cn } from '@/lib/utils';

export const Indicator: FC = () => {
  const [isMuted, setIsMuted] = useState(true);
  const { socket } = useSocket();

  const handleData = useCallback(({ muted }: { muted: boolean }) => {
    setIsMuted(muted);
  }, []);

  useEffect(() => {
    socket.on('obs:microphone', handleData);

    return () => {
      socket.off('obs:microphone', handleData);
    };
  }, []);

  return (
    <div
      className={cn(
        isMuted
          ? 'bg-red-600 shadow-[2px_0_12px_theme(colors.red.600)]'
          : 'bg-main-avagreen shadow-[2px_0_12px_theme(colors.main.avagreen)]',
        'absolute -right-3 top-0 z-50 h-36 w-1 rounded-l-sm transition-colors'
      )}
    ></div>
  );
};

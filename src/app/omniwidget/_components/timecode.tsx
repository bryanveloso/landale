'use client';

import { Karla } from 'next/font/google';
import type { OBSResponseTypes } from 'obs-websocket-js';
import { FC, useCallback, useEffect, useState } from 'react';

import { useSocket } from '@/lib/socket.provider';
import { cn } from '@/lib/utils';

const karla = Karla({ subsets: ['latin'], preload: true, display: 'swap' });

export const Timecode: FC = () => {
  const [isLoading, setIsLoading] = useState(true);

  const { socket, isConnected } = useSocket();

  const [hours, setHours] = useState<string>('00');
  const [minutes, setMinutes] = useState<string>('00');
  const [seconds, setSeconds] = useState<string>('00');

  const handleData = useCallback(
    (data: OBSResponseTypes['GetStreamStatus']) => {
      const { outputTimecode } = data;
      const timecode = outputTimecode.slice(0, -4);
      const [hours, minutes, seconds] = timecode.split(':');

      setHours(hours);
      setMinutes(minutes);
      setSeconds(seconds);
    },
    []
  );

  useEffect(() => {
    socket.on('obs:status', handleData);

    return () => {
      socket.off('obs:status', handleData);
    };
  }, [socket, isConnected, handleData]);

  if (isLoading) {
    // throw new Promise(resolve => {});
  }

  return (
    <div
      className={cn(
        'flex flex-auto items-end text-xl tabular-nums',
        karla.className
      )}
    >
      <div className="pr-0.5">
        <span className="text-3xl">{hours}</span>
        <span className="font-semibold opacity-60">h</span>
      </div>
      <div className="pr-0.5">
        <span className="text-3xl">{minutes}</span>
        <span className="font-semibold opacity-60">m</span>
      </div>
      <div className="pr-0.5">
        <span className="text-3xl">{seconds}</span>
        <span className="font-semibold opacity-60">s</span>
      </div>
    </div>
  );
};

'use client';

import { useSocket } from '@/lib/socket.provider';

import { Ticker } from './_components/ticker';
import { Tracker } from './_components/tracker';
import { useEffect } from 'react';

/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  const { socket } = useSocket();

  const handleData = (data: any) => {
    console.log(data);
  };

  useEffect(() => {
    socket.on('bizhawk:message', handleData);

    return () => {
      socket.off('bizhawk:message', handleData);
    };
  }, [socket]);

  return (
    <>
      <Tracker />
      {/* <Ticker /> */}
    </>
  );
};

export default Page;

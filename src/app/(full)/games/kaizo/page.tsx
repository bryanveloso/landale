'use client';

import { Ticker } from './_components/ticker';
import { Tracker } from './_components/tracker';

/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  return (
    <main className="flex h-screen flex-col">
      <Tracker />
      <Ticker />

      {/* "Fake" Sidebar */}
      <div className="absolute -z-10 ml-[1499px] flex">
        <div className="h-screen w-3 bg-black"></div>
        <div className="h-screen w-3  bg-gradient-to-b from-shark-900 to-shark-950"></div>
      </div>
    </main>
  );
};

export default Page;

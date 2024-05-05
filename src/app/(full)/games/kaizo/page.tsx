import Image from 'next/image';

import ava from '~/public/games/kaizo/ava_full.png';

/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  return (
    <div className="flex justify-end">
      <div className="m-6 flex flex-col">
        <div className="flex h-36 items-end justify-end overflow-hidden">
          <div className="flex basis-full flex-col p-4 pl-20">
            <div className="font-mono text-lg font-bold text-main-avayellow">
              #615
            </div>
            <div className="text-2xl font-bold text-shark-100">Koga</div>
            <div className="font-bold text-shark-500">PERSONAL BEST</div>
          </div>
          <div className="flex-none self-start pr-2">
            <Image src={ava} alt="Ava" width={140} height={316} priority />
          </div>
        </div>
        <div className="flex rounded-2xl bg-gradient-to-b from-shark-800 to-shark-900 shadow-xl shadow-black/50">
          <div className="relative m-3 flex rounded-lg bg-shark-950 p-3 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
            <div className="h-[416px] w-96 bg-red-500"></div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Page;

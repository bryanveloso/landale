'use client';

import { useKaizoAttempts } from '@/hooks/use-kaizo-attempts';

/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  const { data, status } = useKaizoAttempts();

  const Statistics = () => (
    <div className="flex flex-auto flex-col gap-y-1.5 px-3 pb-3">
      <div className="flex justify-between p-1 py-0.5 text-shark-100">
        <div className="flex items-center">
          <span className="rounded p-1 px-2 ring-1 ring-shark-800">
            <span className="font-semibold opacity-60">ATTEMPT</span>
          </span>
          <span className="pl-3 text-xl font-semibold">{data?.attempts}</span>
        </div>
        <div className="flex items-center">
          <span className="rounded p-1 px-2 ring-1 ring-shark-800">
            <span className="font-semibold opacity-60">PB</span>
          </span>
          <span className="pl-3 text-xl font-semibold">Surge</span>
        </div>
      </div>
    </div>
  );

  return (
    <main className="flex items-start justify-end">
      <div className="m-6 flex flex-col items-start">
        <div className="flex rounded-2xl bg-gradient-to-b from-shark-800 to-shark-900 shadow-xl shadow-black/50">
          <div className="relative m-3 flex rounded-lg bg-shark-950 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
            <div className="bg-shark-950 p-3">
              <div className="h-[416px] w-96 bg-red-500"></div>
              <Statistics />
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Page;

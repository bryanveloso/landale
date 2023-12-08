'use client';

import { useSearchParams } from 'next/navigation';

/**
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  const searchParams = useSearchParams();
  const width = searchParams.get('width');

  return (
    <main className="flex items-start justify-start">
      <div className="m-6 flex items-start">
        <div className="flex rounded-2xl bg-gradient-to-b from-shark-800 to-shark-900 shadow-xl shadow-black/50">
          <div className="relative m-3 flex rounded-lg bg-shark-950 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
            <div className="bg-shark-950 p-3">
              <div
                className={`aspect-video bg-red-500`}
                style={{ width: `${width ?? 384}px` }}
              ></div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Page;

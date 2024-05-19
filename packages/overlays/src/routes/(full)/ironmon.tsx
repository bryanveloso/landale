import { createFileRoute } from '@tanstack/react-router';

import { Slot } from '@/components/slot';
import { Seed } from '@/components/ironmon/seed';
import { Statistics } from '@/components/ironmon/statistics';

export const Route = createFileRoute('/(full)/ironmon')({
  component: Ironmon,
});

function Ironmon() {
  return (
    <div className="relative flex h-canvas w-canvas flex-col justify-between">
      {/* Sidebar */}
      <aside className="flex justify-end">
        <div className="m-6 flex flex-col gap-3">
          <Slot width="w-96">
            <div className="h-[416px] bg-avayellow" />
            <Statistics />
          </Slot>
        </div>
      </aside>

      {/* Seed Display */}
      <div className="flex justify-start">
        <div className="m-6 flex flex-col">
          <div className="flex rounded-2xl bg-shark-800 bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl shadow-black/50 ring-2 ring-inset ring-white/10">
            <div className="relative m-3 rounded-lg bg-shark-950 p-1.5">
              <div className="flex items-center gap-1">
                <div className="flex h-12 flex-auto grow items-center gap-3 rounded bg-shark-950 bg-gradient-to-b from-white/20 to-black/20 px-4 bg-blend-soft-light ring-2 ring-inset ring-white/10">
                  <div className="relative -top-1.5 left-8 -ml-12">
                    <img src="./games/kaizo/ava.png" />
                  </div>
                  <div className="rounded bg-avayellow px-2 pl-6 font-black">
                    SEED
                  </div>
                  <div className="text-2xl font-bold tabular-nums text-avayellow">
                    <Seed />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Location Widget */}
      <div className="absolute bottom-[40px] right-[84px] -z-10 h-canvas w-[302px] bg-black">
        <img src="/1.png?url" />
      </div>
    </div>
  );
}

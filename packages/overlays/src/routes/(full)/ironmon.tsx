import { createFileRoute } from '@tanstack/react-router'

import { Slot } from '@/components/slot'
import { Seed } from '@/components/ironmon/seed'
import { Statistics } from '@/components/ironmon/statistics'
import { IronmonProvider } from '@/lib/providers/ironmon'

export const Route = createFileRoute('/(full)/ironmon')({
  component: Ironmon
})

function Ironmon() {
  return (
    <IronmonProvider>
      <div className="h-canvas w-canvas relative flex flex-col justify-between">
        {/* Sidebar */}
        <aside className="flex justify-end">
          <div className="m-6 flex flex-col gap-3">
            <Slot width="w-96">
              <div className="bg-avayellow h-[416px]" />
              <Statistics />
            </Slot>
          </div>
        </aside>

        {/* Seed Display */}
        <div className="flex justify-start">
          <div className="m-6 flex flex-col">
            <div className="bg-shark-800 flex rounded-2xl bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl ring-2 shadow-black/50 ring-white/10 ring-inset">
              <div className="bg-shark-950 relative m-3 rounded-lg p-1.5">
                <div className="flex items-center gap-1">
                  <div className="bg-shark-950 flex h-12 flex-auto grow items-center gap-3 rounded bg-gradient-to-b from-white/20 to-black/20 px-4 bg-blend-soft-light ring-2 ring-white/10 ring-inset">
                    <div className="relative -top-1.5 left-8 -ml-12">
                      <img src="./games/kaizo/ava.png" />
                    </div>
                    <div className="bg-avayellow rounded px-2 pl-6 font-black">SEED</div>
                    <div className="text-avayellow text-2xl font-bold tabular-nums">
                      <Seed />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Location Widget */}
        <div className="h-canvas absolute right-[84px] bottom-[40px] -z-10 w-[302px] bg-black">
          <img src="/1.png?url" />
        </div>
      </div>
    </IronmonProvider>
  )
}

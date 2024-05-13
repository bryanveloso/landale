import { createFileRoute } from '@tanstack/react-router';

import { Slot } from '@/components/slot';
import { Seed } from '@/components/ironmon/seed';

export const Route = createFileRoute('/(full)/ironmon')({
  component: Ironmon,
});

function Ironmon() {
  return (
    <div className="w-canvas h-canvas relative flex flex-col justify-between">
      {/* Sidebar */}
      <aside className="flex justify-end">
        <div className="m-6 flex flex-col">
          <div className="flex h-36 items-end justify-end overflow-hidden">
            <div className="text-avayellow">
              <Seed />
            </div>
          </div>
          <Slot width="w-96" height="h-[416px]" />
        </div>
      </aside>

      {/* Location Widget */}
      <div className="h-canvas absolute right-[84px] bottom-[40px] -z-10 w-[302px] bg-black"></div>
    </div>
  );
}

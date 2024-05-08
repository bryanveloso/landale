import { createFileRoute } from '@tanstack/react-router';

import { Slot } from '@/components/slot';

export const Route = createFileRoute('/(full)/ironmon')({
  component: Ironmon,
});

function Ironmon() {
  return (
    <div className="w-canvas h-canvas flex flex-col">
      {/* Sidebar */}
      <aside className="flex justify-end">
        <div className="m-6 flex flex-col">
          <div className="flex h-36 items-end justify-end overflow-hidden"></div>
          <Slot width="w-96" height="h-[416px]" />
        </div>
      </aside>

      {/* Fake Separator */}
      <div className="absolute -z-10 ml-[1499px] flex">
        <div className="h-canvas w-3 bg-black"></div>
        <div className="h-canvas bg-shark-950 w-3"></div>
      </div>
    </div>
  );
}

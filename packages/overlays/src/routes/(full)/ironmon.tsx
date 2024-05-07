import { createFileRoute } from '@tanstack/react-router';

import { Slot } from '@/components/slot';

export const Route = createFileRoute('/(full)/ironmon')({
  component: Ironmon,
});

function Ironmon() {
  return (
    <div className="h-canvas w-canvas relative">
      {/* Sidebar */}
      <aside className="flex justify-end">
        <div className="m-6 flex flex-col">
          <div className="flex h-36 items-end justify-end overflow-hidden"></div>
          <Slot width="w-96" height="h-[416px]" />
        </div>
      </aside>

      {/* Fake Separator */}
      <div className="absolute top-0 -z-10 ml-[1499px] flex">
        <div className="h-canvas w-3 bg-black"></div>
        <div className="from-shark-900 to-shark-950 h-canvas w-3 bg-gradient-to-b"></div>
      </div>
    </div>
  );
}

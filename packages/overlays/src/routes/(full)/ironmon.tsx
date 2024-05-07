import { createFileRoute } from '@tanstack/react-router';

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
          <div className="from-shark-800 to-shark-900 flex rounded-2xl bg-gradient-to-b shadow-xl shadow-black/50">
            <div className="bg-shark-950 relative m-3 flex rounded-lg p-3 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
              <div className="bg-avayellow h-[416px] w-96"></div>
            </div>
          </div>
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

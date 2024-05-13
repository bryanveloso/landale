import { createFileRoute } from '@tanstack/react-router';

import avalonstar from '~/avalonstar.png';

export const Route = createFileRoute('/(widget)/omnywidget')({
  component: Omnywidget,
});

function Omnywidget() {
  return (
    <div className="w-canvas h-canvas relative flex flex-col justify-between">
      {/* Widget */}
      <div className="flex justify-end">
        <div className="m-6 flex flex-col">
          <div className="bg-shark-800 flex rounded-2xl ring-2 shadow-xl shadow-black/50 ring-white/10 ring-inset">
            <div className="bg-shark-950 relative m-3 rounded-lg p-1.5 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
              <div className="flex w-96 items-center gap-1">
                <div className="bg-muted-bluegrey h-12 flex-auto grow rounded ring-2 ring-white/30 ring-inset"></div>
                <div className="m-2 w-8">
                  <img src={avalonstar} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

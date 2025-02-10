import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/(widget)/omnywidget')({
  component: Omnywidget,
});

function Omnywidget() {
  return (
    <div className="relative flex h-canvas w-canvas flex-col justify-between">
      {/* Widget */}
      <div className="flex justify-end">
        <div className="m-6 flex flex-col">
          <div className="flex rounded-2xl bg-shark-800 bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl shadow-black/50 ring-2 ring-inset ring-white/10">
            <div className="relative m-3 rounded-lg bg-shark-950 p-1.5 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
              <div className="flex w-96 items-center gap-1">
                <div className="h-12 flex-auto grow rounded bg-shark-950 bg-gradient-to-b from-white/20 to-black/20 p-3 pl-4 text-white bg-blend-soft-light ring-2 ring-inset ring-white/10">
                  <strong className="font-bold tracking-wide text-avayellow/50"></strong>
                </div>
                <div className="m-2 w-8">
                  <img src="./avalonstar.png" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

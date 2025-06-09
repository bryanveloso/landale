import { createFileRoute } from '@tanstack/react-router'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(widget)/omnywidget')({
  component: Omnywidget
})

function Omnywidget() {
  return (
    <ErrorBoundary>
      <div className="h-canvas w-canvas relative flex flex-col justify-between">
        {/* Widget */}
        <div className="flex justify-end">
          <div className="m-6 flex flex-col">
            <div className="bg-shark-800 flex rounded-2xl bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl ring-2 shadow-black/50 ring-white/10 ring-inset">
              <div className="bg-shark-950 shadow-[inset_0_0_0_1px_theme(colors.shark.950)] relative m-3 rounded-lg p-1.5">
                <div className="flex w-96 items-center gap-1">
                  <div className="bg-shark-950 h-12 flex-auto grow rounded bg-gradient-to-b from-white/20 to-black/20 p-3 pl-4 text-white bg-blend-soft-light ring-2 ring-white/10 ring-inset">
                    <strong className="text-avayellow/50 font-bold tracking-wide"></strong>
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
    </ErrorBoundary>
  )
}

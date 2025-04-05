import { createFileRoute } from '@tanstack/react-router'

import { Slot } from '@/components/slot'

export const Route = createFileRoute('/(full)/speedrunning')({
  component: Speedrunning
})

function Speedrunning() {
  return (
    <div className="h-canvas w-canvas relative flex flex-col justify-between">
      {/* Sidebar */}
      <aside className="flex justify-end">
        <div className="m-6 flex flex-col gap-3">
          <Slot width="w-96">
            <div className="h-[636px]" />
          </Slot>
        </div>
      </aside>
    </div>
  )
}

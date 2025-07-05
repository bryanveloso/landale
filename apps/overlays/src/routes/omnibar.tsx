import { createFileRoute } from '@tanstack/solid-router'
import { Omnibar } from '@/components/omnibar'

export const Route = createFileRoute('/omnibar')({
  component: RouteComponent
})

function RouteComponent() {
  return (
    <div class="w-canvas h-canvas flex items-end">
      <Omnibar />
    </div>
  )
}

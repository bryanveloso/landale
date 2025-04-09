import { useRive } from '@rive-app/react-canvas'
import { createFileRoute } from '@tanstack/react-router'

import LandaleRive from '@/assets/landale.riv?url'

export const Route = createFileRoute('/(full)/rive')({
  component: RouteComponent
})

function RouteComponent() {
  const { rive, RiveComponent } = useRive({
    src: LandaleRive
  })

  return (
    <div className="aspect-video h-[1080px]">
      <RiveComponent />
    </div>
  )
}

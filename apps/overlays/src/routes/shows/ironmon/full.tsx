import { createFileRoute } from '@tanstack/solid-router'

export const Route = createFileRoute('/shows/ironmon/full')({
  component: RouteComponent,
})

function RouteComponent() {
  return <div>Hello "/shows/ironmon/full"!</div>
}

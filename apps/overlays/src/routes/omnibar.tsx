import { createFileRoute } from '@tanstack/solid-router'

export const Route = createFileRoute('/omnibar')({
  component: RouteComponent,
})

function RouteComponent() {
  return <div>Hello "/omnibar"!</div>
}

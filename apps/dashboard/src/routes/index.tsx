import { createFileRoute } from '@tanstack/solid-router'
import { StreamQueue } from '../components/stream-queue/index'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return (
    <div>
      <StreamQueue />
    </div>
  )
}

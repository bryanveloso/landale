import { createFileRoute } from '@tanstack/solid-router'
import { Omnibar } from '@/components/omnibar'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return <Omnibar />
}

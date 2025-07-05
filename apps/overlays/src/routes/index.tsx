import { createFileRoute } from '@tanstack/solid-router'
import { Omnibar } from '../components/omni-bar'

export const Route = createFileRoute('/')({
  component: Index
})

function Index() {
  return <Omnibar serverUrl="ws://localhost:7175/socket" />
}

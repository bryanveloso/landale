import { createFileRoute } from '@tanstack/react-router'
import { StatusBar } from '@/components/status-bar'

export const Route = createFileRoute('/(widget)/status-bar')({
  component: StatusBarWidget
})

function StatusBarWidget() {
  return <StatusBar />
}
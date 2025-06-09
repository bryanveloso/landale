import { createFileRoute } from '@tanstack/react-router'
import { StatusText } from '@/components/status-text'

export const Route = createFileRoute('/(widget)/status-text')({
  component: StatusTextWidget
})

function StatusTextWidget() {
  return <StatusText />
}

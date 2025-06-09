import { createFileRoute } from '@tanstack/react-router'
import { StatusBar } from '@/components/status-bar'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(widget)/status-bar')({
  component: StatusBarWidget
})

function StatusBarWidget() {
  return (
    <ErrorBoundary>
      <StatusBar />
    </ErrorBoundary>
  )
}

import { createFileRoute } from '@tanstack/react-router'
import { StatusText } from '@/components/status-text'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(widget)/status-text')({
  component: StatusTextWidget
})

function StatusTextWidget() {
  return (
    <ErrorBoundary>
      <StatusText />
    </ErrorBoundary>
  )
}

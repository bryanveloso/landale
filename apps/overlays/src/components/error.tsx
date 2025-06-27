import { ErrorComponent, type ErrorComponentProps } from '@tanstack/react-router'
import { logger } from '@/lib/logger'

export const DefaultCatchBoundary = ({ error }: ErrorComponentProps) => {
  logger.error('Router error boundary caught an error', {
    error: error as Error
  })

  return <ErrorComponent error={error} />
}

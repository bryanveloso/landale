'use client'

import { Component, type ReactNode } from 'react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { AlertCircle } from 'lucide-react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error?: Error
}

export class MonitoringErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  override componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('Monitoring component error:', error, errorInfo)
  }

  override render() {
    if (this.state.hasError) {
      return (
        this.props.fallback || (
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertTitle>Monitoring Error</AlertTitle>
            <AlertDescription>
              Failed to load monitoring data. Please refresh the page.
              {this.state.error && (
                <details className="mt-2">
                  <summary className="cursor-pointer text-sm">Error details</summary>
                  <pre className="mt-2 overflow-auto text-xs">{this.state.error.message}</pre>
                </details>
              )}
            </AlertDescription>
          </Alert>
        )
      )
    }

    return this.props.children
  }
}

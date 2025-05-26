import { Component, type ErrorInfo, type ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo)
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback
      }

      return (
        <div className="flex h-screen w-screen items-center justify-center bg-black/80 text-white">
          <div className="max-w-md rounded-lg bg-red-950/50 p-6 text-center ring-1 ring-red-500/20">
            <h2 className="mb-2 text-xl font-bold">Overlay Error</h2>
            <p className="mb-4 text-sm text-red-200">Something went wrong. The overlay will recover automatically.</p>
            <details className="text-xs text-red-300">
              <summary className="cursor-pointer">Error details</summary>
              <pre className="mt-2 overflow-auto rounded bg-black/50 p-2 text-left">
                {this.state.error?.message}
              </pre>
            </details>
          </div>
        </div>
      )
    }

    return this.props.children
  }
}
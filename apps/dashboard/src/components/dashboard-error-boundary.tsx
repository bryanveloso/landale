/**
 * Dashboard Error Boundary
 *
 * Handles errors in dashboard components while maintaining functionality.
 * Provides user-friendly error messages and recovery options.
 */

import { createSignal, ErrorBoundary } from 'solid-js'
import type { JSX } from 'solid-js'

interface DashboardErrorBoundaryProps {
  children: JSX.Element
  fallback?: JSX.Element
  componentName?: string
  onError?: (error: Error, errorInfo: any) => void
}

interface ErrorState {
  hasError: boolean
  error: Error | null
  errorInfo: any
  timestamp: string
}

export function DashboardErrorBoundary(props: DashboardErrorBoundaryProps) {
  const [errorState, setErrorState] = createSignal<ErrorState>({
    hasError: false,
    error: null,
    errorInfo: null,
    timestamp: ''
  })

  const handleError = (error: Error, errorInfo: any) => {
    const timestamp = new Date().toISOString()
    
    setErrorState({
      hasError: true,
      error,
      errorInfo,
      timestamp
    })

    // Log the error with context
    console.error(`🚨 Dashboard Error [${props.componentName || 'unknown'}]:`, error.message, {
      error,
      errorInfo,
      timestamp
    })

    // Call parent error handler if provided
    props.onError?.(error, errorInfo)
  }

  const retry = () => {
    setErrorState({
      hasError: false,
      error: null,
      errorInfo: null,
      timestamp: ''
    })
    
    console.log('🔄 Retrying dashboard component:', props.componentName || 'unknown')
  }

  const DefaultFallback = () => {
    const state = errorState()
    
    return (
      <div 
        data-error-boundary
        data-component={props.componentName}
        style={{
          background: 'linear-gradient(135deg, #fee2e2, #fecaca)',
          border: '1px solid #f87171',
          'border-radius': '8px',
          padding: '16px',
          margin: '8px',
          'font-family': 'system-ui, sans-serif'
        }}
      >
        <div style={{ 
          display: 'flex', 
          'align-items': 'center', 
          'margin-bottom': '12px',
          color: '#dc2626'
        }}>
          <span style={{ 'font-size': '18px', 'margin-right': '8px' }}>⚠️</span>
          <span style={{ 'font-weight': '600', 'font-size': '14px' }}>
            {props.componentName || 'Component'} Error
          </span>
        </div>
        
        <div style={{ 
          'margin-bottom': '12px', 
          'font-size': '13px',
          color: '#7f1d1d',
          'line-height': '1.4'
        }}>
          {state.error?.message || 'An unexpected error occurred'}
        </div>
        
        <div style={{ 
          'margin-bottom': '12px', 
          'font-size': '11px',
          color: '#6b7280',
          'font-family': 'monospace'
        }}>
          {state.timestamp}
        </div>
        
        <div style={{ display: 'flex', gap: '8px' }}>
          <button
            onClick={retry}
            style={{
              background: '#dc2626',
              color: 'white',
              border: 'none',
              padding: '6px 12px',
              'border-radius': '4px',
              cursor: 'pointer',
              'font-size': '12px',
              'font-weight': '500'
            }}
          >
            Retry
          </button>
          
          <button
            onClick={() => window.location.reload()}
            style={{
              background: '#6b7280',
              color: 'white',
              border: 'none',
              padding: '6px 12px',
              'border-radius': '4px',
              cursor: 'pointer',
              'font-size': '12px'
            }}
          >
            Reload Page
          </button>
        </div>
      </div>
    )
  }

  return (
    <ErrorBoundary
      fallback={(error, reset) => {
        // Update our error state when ErrorBoundary catches something
        if (!errorState().hasError) {
          handleError(error, { reset })
        }
        
        return props.fallback || <DefaultFallback />
      }}
    >
      {props.children}
    </ErrorBoundary>
  )
}
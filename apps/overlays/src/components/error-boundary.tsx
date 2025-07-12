/**
 * Error Boundary for Overlay Components
 *
 * Prevents cascade failures by isolating errors at the layer level.
 * When one layer fails, other layers continue to function normally.
 */

import { createSignal, ErrorBoundary } from 'solid-js'
import type { JSX } from 'solid-js'

interface OverlayErrorBoundaryProps {
  children: JSX.Element
  fallback?: JSX.Element
  layerName?: string
  onError?: (error: Error, errorInfo: any) => void
}

interface ErrorState {
  hasError: boolean
  error: Error | null
  errorInfo: any
  timestamp: string
}

export function OverlayErrorBoundary(props: OverlayErrorBoundaryProps) {
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
    console.error(`🎭 Overlay Error [${props.layerName || 'unknown'}]:`, error.message, {
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
    
    console.log('🔄 Retrying overlay layer:', props.layerName || 'unknown')
  }

  const DefaultFallback = () => (
    <div 
      data-error-boundary
      data-layer={props.layerName}
      style={{
        position: 'absolute',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        background: 'rgba(255, 0, 0, 0.8)',
        color: 'white',
        padding: '20px',
        'border-radius': '8px',
        'font-family': 'monospace',
        'font-size': '14px',
        'max-width': '400px',
        'z-index': 9999,
        border: '2px solid #ff4444'
      }}
    >
      <div style={{ 'font-weight': 'bold', 'margin-bottom': '10px' }}>
        ⚠️ Layer Error: {props.layerName || 'Unknown'}
      </div>
      
      <div style={{ 'margin-bottom': '10px', 'font-size': '12px' }}>
        {errorState().error?.message || 'Unknown error occurred'}
      </div>
      
      <div style={{ 'margin-bottom': '15px', 'font-size': '11px', opacity: 0.8 }}>
        {errorState().timestamp}
      </div>
      
      <button
        onClick={retry}
        style={{
          background: '#ff4444',
          color: 'white',
          border: 'none',
          padding: '8px 16px',
          'border-radius': '4px',
          cursor: 'pointer',
          'font-size': '12px'
        }}
      >
        Retry Layer
      </button>
    </div>
  )

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
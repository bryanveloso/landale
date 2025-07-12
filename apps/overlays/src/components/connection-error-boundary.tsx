/**
 * Connection Error Boundary
 *
 * Handles WebSocket connection failures and provides automatic retry logic.
 * Shows degraded UI when server is unavailable.
 */

import { createSignal, createEffect, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { useSocket } from '@landale/shared'

interface ConnectionErrorBoundaryProps {
  children: JSX.Element
  fallback?: JSX.Element
  maxRetries?: number
  retryInterval?: number
}

export function ConnectionErrorBoundary(props: ConnectionErrorBoundaryProps) {
  const { isConnected, reconnectAttempts } = useSocket()
  const [showFallback, setShowFallback] = createSignal(false)
  const [isRetrying, setIsRetrying] = createSignal(false)
  
  const maxRetries = props.maxRetries || 5
  const retryInterval = props.retryInterval || 2000

  // Monitor connection state
  createEffect(() => {
    const connected = isConnected()
    const attempts = reconnectAttempts()
    
    if (!connected && attempts > maxRetries) {
      console.warn(`🔌 Connection failed after ${attempts}/${maxRetries} retries`)
      setShowFallback(true)
      setIsRetrying(false)
    } else if (!connected && attempts > 0) {
      console.log(`🔌 Connection retry ${attempts}/${maxRetries} in progress`)
      setIsRetrying(true)
    } else if (connected) {
      console.log('🔌 Connection restored')
      setShowFallback(false)
      setIsRetrying(false)
    }
  })

  const forceRetry = async () => {
    setIsRetrying(true)
    setShowFallback(false)
    
    console.log('🔌 Manual connection retry triggered')
    
    // Give some time for the retry attempt
    setTimeout(() => {
      if (!isConnected()) {
        setShowFallback(true)
        setIsRetrying(false)
      }
    }, retryInterval)
  }

  const DefaultFallback = () => (
    <div 
      data-connection-error
      style={{
        position: 'fixed',
        top: '20px',
        right: '20px',
        background: 'rgba(255, 165, 0, 0.9)',
        color: 'white',
        padding: '15px 20px',
        'border-radius': '8px',
        'font-family': 'system-ui, sans-serif',
        'font-size': '14px',
        'max-width': '300px',
        'z-index': 10000,
        border: '2px solid #ffa500',
        'box-shadow': '0 4px 12px rgba(0,0,0,0.3)'
      }}
    >
      <div style={{ 'font-weight': 'bold', 'margin-bottom': '8px' }}>
        ⚠️ Connection Lost
      </div>
      
      <div style={{ 'margin-bottom': '10px', 'font-size': '13px', opacity: 0.9 }}>
        Unable to connect to stream server after {reconnectAttempts()} attempts.
      </div>
      
      <div style={{ 'margin-bottom': '12px', 'font-size': '12px', opacity: 0.8 }}>
        Overlay functionality may be limited.
      </div>
      
      <button
        onClick={forceRetry}
        disabled={isRetrying()}
        style={{
          background: isRetrying() ? '#999' : '#ff8c00',
          color: 'white',
          border: 'none',
          padding: '6px 12px',
          'border-radius': '4px',
          cursor: isRetrying() ? 'not-allowed' : 'pointer',
          'font-size': '12px',
          width: '100%'
        }}
      >
        {isRetrying() ? 'Retrying...' : 'Retry Connection'}
      </button>
    </div>
  )

  return (
    <>
      {props.children}
      
      <Show when={showFallback()}>
        {props.fallback || <DefaultFallback />}
      </Show>
    </>
  )
}
/**
 * Debug Drawer Component
 *
 * Development-only testing tools for manual alerts, interrupts, and fallback testing.
 * Hidden by default and only shown in development environment or when explicitly enabled.
 */

import { createSignal, For, Show } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import { useStreamCommands } from '@/hooks/use-stream-commands'
import { useLayerState } from '@/hooks/use-layer-state'
import { Button } from './ui/button'
import { handleAsyncOperation } from '@/services/error-handler'

export function DebugDrawer() {
  const { connectionState } = useStreamService()
  const { sendCommand } = useStreamCommands()
  const { layerState } = useLayerState()

  const [isExpanded, setIsExpanded] = createSignal(false)
  const [alertMessage, setAlertMessage] = createSignal('')
  const [alertDuration, setAlertDuration] = createSignal(10000)
  const [isSubmitting, setIsSubmitting] = createSignal(false)
  const [lastAction, setLastAction] = createSignal<string | null>(null)

  const isConnected = () => connectionState().connected
  const isDevelopment = () => import.meta.env.DEV

  // Don't render in production unless explicitly enabled
  const shouldShow = () => isDevelopment() || localStorage.getItem('landale-debug-enabled') === 'true'

  const alertTypes = [
    { id: 'alert', label: 'General Alert', description: 'Breaking news style alert' },
    { id: 'raid_alert', label: 'Raid Alert', description: 'Incoming raid notification' },
    { id: 'host_alert', label: 'Host Alert', description: 'Being hosted notification' },
    { id: 'death_alert', label: 'Death Alert', description: 'IronMON death notification' },
    { id: 'shiny_encounter', label: 'Shiny Pokemon', description: 'Shiny encounter alert' },
    { id: 'elite_four_alert', label: 'Elite Four', description: 'Elite Four challenge' },
    { id: 'build_failure', label: 'Build Failure', description: 'CI/CD build failure' },
    { id: 'deployment_alert', label: 'Deployment', description: 'Deployment notification' }
  ]

  const handleSendAlert = async (alertType: string) => {
    if (!isConnected() || !alertMessage().trim()) return

    setIsSubmitting(true)
    setLastAction(`Sending ${alertType} alert`)

    const result = await handleAsyncOperation(
      () =>
        sendCommand('add_interrupt', {
          type: alertType,
          data: {
            message: alertMessage().trim(),
            manual: true,
            debug: true,
            timestamp: new Date().toISOString()
          },
          duration: alertDuration()
        }),
      {
        component: 'DebugDrawer',
        operation: `send ${alertType} alert`,
        data: { alertType, message: alertMessage().trim(), duration: alertDuration() }
      }
    )

    if (result.success && result.data.status === 'ok') {
      setLastAction(`Successfully sent ${alertType} alert`)
      setAlertMessage('')
    } else {
      const errorMessage = result.success ? `Failed to send alert: ${result.data.error}` : result.error.userMessage
      setLastAction(errorMessage)
    }

    setIsSubmitting(false)
  }

  const handleManualSubTrain = async () => {
    if (!isConnected()) return

    setIsSubmitting(true)
    setLastAction('Starting manual sub train')

    try {
      const response = await sendCommand('add_interrupt', {
        type: 'sub_train',
        data: {
          subscriber: 'Debug User',
          tier: '1000',
          count: 1,
          manual: true,
          debug: true,
          timestamp: new Date().toISOString()
        },
        duration: 300000 // 5 minutes
      })

      if (response.status === 'ok') {
        setLastAction('Successfully started manual sub train')
      } else {
        setLastAction(`Failed to start sub train: ${response.error}`)
      }
    } catch (error) {
      setLastAction(`Error starting sub train: ${error}`)
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleClearInterrupts = async () => {
    if (!isConnected()) return

    setIsSubmitting(true)
    setLastAction('Clearing all interrupts')

    try {
      const response = await sendCommand('clear_interrupts', {
        manual: true,
        debug: true,
        timestamp: new Date().toISOString()
      })

      if (response.status === 'ok') {
        setLastAction('Successfully cleared all interrupts')
      } else {
        setLastAction(`Failed to clear interrupts: ${response.error}`)
      }
    } catch (error) {
      setLastAction(`Error clearing interrupts: ${error}`)
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleTestFallback = async () => {
    if (!isConnected()) return

    setIsSubmitting(true)
    setLastAction('Testing fallback mode')

    try {
      const response = await sendCommand('test_fallback', {
        debug: true,
        timestamp: new Date().toISOString()
      })

      if (response.status === 'ok') {
        setLastAction('Successfully triggered fallback mode')
      } else {
        setLastAction(`Failed to trigger fallback: ${response.error}`)
      }
    } catch (error) {
      setLastAction(`Error triggering fallback: ${error}`)
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleToggleDebug = () => {
    const current = localStorage.getItem('landale-debug-enabled') === 'true'
    localStorage.setItem('landale-debug-enabled', (!current).toString())
    window.location.reload()
  }

  if (!shouldShow()) {
    return (
      <div class="debug-toggle">
        <Button size="sm" variant="outline" onClick={handleToggleDebug} title="Enable debug tools">
          🐛
        </Button>
      </div>
    )
  }

  return (
    <div class="debug-drawer">
      <header class="debug-header">
        <Button onClick={() => setIsExpanded(!isExpanded())} variant="outline" size="sm" disabled={!isConnected()}>
          🐛 Debug Tools {isExpanded() ? '▼' : '▶'}
        </Button>
        <div class="connection-status">{isConnected() ? '🟢 Connected' : '🔴 Disconnected'}</div>
        <Button size="sm" variant="outline" onClick={handleToggleDebug} title="Disable debug tools">
          ✕
        </Button>
      </header>

      <Show when={isExpanded()}>
        <main class="debug-content">
          {/* Manual Alert Testing */}
          <section class="debug-section">
            <h4>Manual Alerts</h4>
            <div class="alert-input">
              <input
                type="text"
                placeholder="Alert message..."
                value={alertMessage()}
                onInput={(e) => setAlertMessage(e.target.value)}
                disabled={!isConnected() || isSubmitting()}
              />
              <div class="duration-input">
                <label>Duration (ms):</label>
                <input
                  type="number"
                  min="1000"
                  max="60000"
                  step="1000"
                  value={alertDuration()}
                  onInput={(e) => setAlertDuration(parseInt(e.target.value) || 10000)}
                  disabled={!isConnected() || isSubmitting()}
                />
              </div>
            </div>
            <div class="alert-buttons">
              <For each={alertTypes}>
                {(alertType) => (
                  <Button
                    onClick={() => handleSendAlert(alertType.id)}
                    disabled={!isConnected() || isSubmitting() || !alertMessage().trim()}
                    size="sm"
                    variant="outline"
                    title={alertType.description}>
                    {alertType.label}
                  </Button>
                )}
              </For>
            </div>
          </section>

          {/* Quick Test Actions */}
          <section class="debug-section">
            <h4>Quick Actions</h4>
            <div class="quick-actions">
              <Button
                onClick={handleManualSubTrain}
                disabled={!isConnected() || isSubmitting()}
                size="sm"
                variant="outline"
                title="Start a manual sub train for testing">
                Test Sub Train
              </Button>
              <Button
                onClick={handleTestFallback}
                disabled={!isConnected() || isSubmitting()}
                size="sm"
                variant="outline"
                title="Test fallback mode functionality">
                Test Fallback
              </Button>
              <Button
                onClick={handleClearInterrupts}
                disabled={!isConnected() || isSubmitting()}
                size="sm"
                variant="destructive"
                title="Clear all active interrupts">
                Clear All
              </Button>
            </div>
          </section>

          {/* Status Display */}
          <Show when={lastAction()}>
            <div class="debug-status">
              <div class="status-label">Last Action:</div>
              <div class="status-message">{lastAction()}</div>
            </div>
          </Show>

          <Show when={isSubmitting()}>
            <div class="submitting-indicator">Processing...</div>
          </Show>

          {/* System Info */}
          <Show when={isDevelopment()}>
            <section class="debug-section">
              <h4>System Info</h4>
              <div class="system-info">
                <div>Environment: {import.meta.env.MODE}</div>
                <div>Current Show: {layerState().current_show}</div>
                <div>Active Content: {layerState().active_content?.type || 'None'}</div>
                <div>Interrupt Count: {layerState().interrupt_stack.length}</div>
                <div>Version: {layerState().version}</div>
              </div>
            </section>
          </Show>
        </main>
      </Show>
    </div>
  )
}

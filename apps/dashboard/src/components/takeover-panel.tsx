/**
 * Takeover Panel Component
 *
 * Manual overlay takeover controls for full-screen content and streaming interruptions.
 * Uses useStreamCommands for clean command/query separation.
 */

import { createSignal } from 'solid-js'
import { useStreamCommands } from '@/hooks/use-stream-commands'
import { useLayerState } from '@/hooks/use-layer-state'
import type { TakeoverCommand } from '@/types/stream'
import { Button } from './ui/button'
import { createLogger } from '@landale/logger/browser'

const logger = createLogger({
  service: 'dashboard'
})

export function TakeoverPanel() {
  const commands = useStreamCommands()
  const { isConnected } = useLayerState()
  const [takeoverText, setTakeoverText] = createSignal('')
  const [duration, setDuration] = createSignal(10)
  const [lastSent, setLastSent] = createSignal('')
  const [takeoverType, setTakeoverType] = createSignal<TakeoverCommand['type']>('technical-difficulties')

  const sendTakeover = async () => {
    if (takeoverType() !== 'screen-cover' && !takeoverText().trim()) {
      logger.error('No message provided for non-screen-cover takeover', {})
      return
    }

    const takeoverData: TakeoverCommand = {
      type: takeoverType(),
      message: takeoverText().trim(),
      duration: duration() * 1000
    }

    logger.info(`Sending takeover: ${takeoverData.type}`, {})

    try {
      await commands.sendTakeover(takeoverData)
      setLastSent(new Date().toLocaleTimeString())
      setTakeoverText('')
    } catch (error) {
      logger.error('Failed to send takeover', {
        error: error instanceof Error ? { message: error.message, stack: error.stack } : { message: String(error) }
      })
    }
  }

  const clearTakeover = async () => {
    try {
      await commands.clearTakeover()
    } catch (error) {
      logger.error('Failed to clear takeover', {
        error: error instanceof Error ? { message: error.message, stack: error.stack } : { message: String(error) }
      })
    }
  }

  const replayLastTakeover = () => {
    if (lastSent()) {
      setTakeoverText(`REPLAY: ${lastSent()}`)
    }
  }

  const takeoverTypes = [
    { value: 'technical-difficulties', label: 'Technical Difficulties' },
    { value: 'screen-cover', label: 'Screen Cover' },
    { value: 'please-stand-by', label: 'Please Stand By' },
    { value: 'custom', label: 'Custom Message' }
  ]

  const quickTakeovers = [
    { type: 'technical-difficulties', text: 'Technical Difficulties - BRB!', duration: 30 },
    { type: 'screen-cover', text: '', duration: 10 },
    { type: 'please-stand-by', text: 'Stream will resume shortly', duration: 15 }
  ]

  return (
    <div>
      {/* Takeover Type Selection */}
      <div>
        <select
          value={takeoverType()}
          onInput={(e) => setTakeoverType(e.target.value as TakeoverCommand['type'])}
          disabled={commands.takeoverState().loading}>
          {takeoverTypes.map((type) => (
            <option value={type.value}>{type.label}</option>
          ))}
        </select>
      </div>

      {/* Main Takeover Control */}
      <div>
        <div>
          <input
            type="text"
            value={takeoverText()}
            onInput={(e) => setTakeoverText(e.target.value)}
            placeholder={takeoverType() === 'screen-cover' ? 'Optional message...' : 'Takeover message...'}
            disabled={commands.takeoverState().loading}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !commands.takeoverState().loading) {
                if (takeoverType() === 'screen-cover' || takeoverText().trim()) {
                  sendTakeover()
                }
              }
            }}
          />

          <div>
            <input
              type="number"
              value={duration()}
              onInput={(e) => setDuration(Number(e.target.value))}
              min="5"
              max="180"
              step="5"
            />
            <span>sec</span>
          </div>
        </div>

        <div>
          <Button
            onClick={sendTakeover}
            disabled={
              (takeoverType() !== 'screen-cover' && !takeoverText().trim()) ||
              commands.takeoverState().loading ||
              !isConnected()
            }>
            {commands.takeoverState().loading ? 'Sending...' : 'Send Takeover'}
          </Button>

          <Button onClick={clearTakeover} disabled={commands.takeoverState().loading || !isConnected()}>
            Clear
          </Button>
        </div>
      </div>

      {/* Quick Takeover Actions */}
      <div>
        {quickTakeovers.map((takeover) => (
          <Button
            onClick={() => {
              setTakeoverType(takeover.type as TakeoverCommand['type'])
              setTakeoverText(takeover.text)
              setDuration(takeover.duration)
            }}
            disabled={commands.takeoverState().loading}>
            {takeover.type === 'screen-cover' ? 'Screen Cover' : takeover.text}
          </Button>
        ))}
      </div>

      {/* Status Info */}
      <div>
        {commands.takeoverState().error && <div>Error: {commands.takeoverState().error}</div>}

        {commands.takeoverState().lastExecuted && (
          <div>Last executed: {new Date(commands.takeoverState().lastExecuted!).toLocaleTimeString()}</div>
        )}

        {lastSent() && (
          <div>
            Last: {lastSent()}
            <Button onClick={replayLastTakeover} disabled={commands.takeoverState().loading}>
              Replay
            </Button>
          </div>
        )}
      </div>

      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div>
          <div>Takeover Loading: {commands.takeoverState().loading ? 'Yes' : 'No'}</div>
          <div>Takeover Error: {commands.takeoverState().error || 'None'}</div>
        </div>
      )}
    </div>
  )
}

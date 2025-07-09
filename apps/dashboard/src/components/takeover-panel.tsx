/**
 * Takeover Panel Component
 * 
 * Manual overlay takeover controls for full-screen content and streaming interruptions.
 * Uses useStreamCommands for clean command/query separation.
 */

import { createSignal } from 'solid-js'
import { useStreamCommands } from '@/hooks/use-stream-commands'
import { useLayerState } from '@/hooks/use-layer-state'
import type { EmergencyOverrideCommand } from '@/types/stream'
import { Button } from './ui/button'

export function TakeoverPanel() {
  const commands = useStreamCommands()
  const { isConnected } = useLayerState()
  const [takeoverText, setTakeoverText] = createSignal('')
  const [duration, setDuration] = createSignal(10)
  const [lastSent, setLastSent] = createSignal('')
  const [takeoverType, setTakeoverType] = createSignal<EmergencyOverrideCommand['type']>('technical-difficulties')

  const sendTakeover = async () => {
    if (takeoverType() !== 'screen-cover' && !takeoverText().trim()) {
      console.error('[TakeoverPanel] No message provided for non-screen-cover takeover')
      return
    }

    const takeoverData: EmergencyOverrideCommand = {
      type: takeoverType(),
      message: takeoverText().trim(),
      duration: duration() * 1000
    }

    console.log('[TakeoverPanel] Sending takeover data:', takeoverData)

    try {
      await commands.sendEmergencyOverride(takeoverData)
      setLastSent(new Date().toLocaleTimeString())
      setTakeoverText('')
    } catch (error) {
      console.error('[TakeoverPanel] Failed to send takeover:', error)
    }
  }

  const clearTakeover = async () => {
    try {
      await commands.clearEmergency()
    } catch (error) {
      console.error('[TakeoverPanel] Failed to clear takeover:', error)
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
          onInput={(e) => setTakeoverType(e.target.value as any)}
          disabled={commands.emergencyState().loading}>
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
            disabled={commands.emergencyState().loading}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !commands.emergencyState().loading) {
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
              commands.emergencyState().loading ||
              !isConnected()
            }>
            {commands.emergencyState().loading ? 'Sending...' : 'Send Takeover'}
          </Button>

          <Button onClick={clearTakeover} disabled={commands.emergencyState().loading || !isConnected()}>
            Clear
          </Button>
        </div>
      </div>

      {/* Quick Takeover Actions */}
      <div>
        {quickTakeovers.map((takeover) => (
          <Button
            onClick={() => {
              setTakeoverType(takeover.type as any)
              setTakeoverText(takeover.text)
              setDuration(takeover.duration)
            }}
            disabled={commands.emergencyState().loading}>
            {takeover.type === 'screen-cover' ? 'Screen Cover' : takeover.text}
          </Button>
        ))}
      </div>

      {/* Status Info */}
      <div>
        {commands.emergencyState().error && <div>Error: {commands.emergencyState().error}</div>}

        {commands.emergencyState().lastExecuted && (
          <div>Last executed: {new Date(commands.emergencyState().lastExecuted!).toLocaleTimeString()}</div>
        )}

        {lastSent() && (
          <div>
            Last: {lastSent()}
            <Button onClick={replayLastTakeover} disabled={commands.emergencyState().loading}>
              Replay
            </Button>
          </div>
        )}
      </div>

      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div>
          <div>Takeover Loading: {commands.emergencyState().loading ? 'Yes' : 'No'}</div>
          <div>Takeover Error: {commands.emergencyState().error || 'None'}</div>
        </div>
      )}
    </div>
  )
}

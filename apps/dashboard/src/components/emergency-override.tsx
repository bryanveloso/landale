/**
 * Emergency Override Component
 * 
 * Uses useStreamCommands for clean command/query separation.
 * No direct WebSocket management - eliminates channel conflicts.
 */

import { createSignal } from 'solid-js'
import { useStreamCommands } from '@/hooks/use-stream-commands'
import { useLayerState } from '@/hooks/use-layer-state'
import type { EmergencyOverrideCommand } from '@/types/stream'

export function EmergencyOverride() {
  const commands = useStreamCommands()
  const { isConnected } = useLayerState()
  const [alertText, setAlertText] = createSignal('')
  const [duration, setDuration] = createSignal(10)
  const [lastSent, setLastSent] = createSignal('')
  const [emergencyType, setEmergencyType] = createSignal<EmergencyOverrideCommand['type']>('technical-difficulties')

  const sendEmergencyOverride = async () => {
    if (emergencyType() !== 'screen-cover' && !alertText().trim()) {
      console.error('[EmergencyOverride] No message provided for non-screen-cover emergency')
      return
    }
    
    const emergencyData: EmergencyOverrideCommand = {
      type: emergencyType(),
      message: alertText().trim(),
      duration: duration() * 1000
    }

    console.log('[EmergencyOverride] Sending emergency data:', emergencyData)

    try {
      await commands.sendEmergencyOverride(emergencyData)
      setLastSent(new Date().toLocaleTimeString())
      setAlertText('')
    } catch (error) {
      console.error('[EmergencyOverride] Failed to send emergency:', error)
    }
  }

  const clearEmergency = async () => {
    try {
      await commands.clearEmergency()
    } catch (error) {
      console.error('[EmergencyOverride] Failed to clear emergency:', error)
    }
  }

  const replayLastAlert = () => {
    if (lastSent()) {
      setAlertText(`REPLAY: ${lastSent()}`)
    }
  }

  const emergencyTypes = [
    { value: 'technical-difficulties', label: 'Technical Difficulties' },
    { value: 'screen-cover', label: 'Screen Cover' },
    { value: 'please-stand-by', label: 'Please Stand By' },
    { value: 'custom', label: 'Custom Message' }
  ]

  const quickEmergencies = [
    { type: 'technical-difficulties', text: 'Technical Difficulties - BRB!', duration: 30 },
    { type: 'screen-cover', text: '', duration: 10 },
    { type: 'please-stand-by', text: 'Stream will resume shortly', duration: 15 }
  ]

  return (
    <div>
      {/* Emergency Type Selection */}
      <div>
        <select
          value={emergencyType()}
          onInput={(e) => setEmergencyType(e.target.value)}
          disabled={commands.emergencyState().loading}
        >
          {emergencyTypes.map(type => (
            <option value={type.value}>{type.label}</option>
          ))}
        </select>
      </div>

      {/* Main Emergency Control */}
      <div>
        <div>
          <input
            type="text"
            value={alertText()}
            onInput={(e) => setAlertText(e.target.value)}
            placeholder={emergencyType() === 'screen-cover' ? 'Optional message...' : 'Emergency message...'}
            disabled={commands.emergencyState().loading}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !commands.emergencyState().loading) {
                if (emergencyType() === 'screen-cover' || alertText().trim()) {
                  sendEmergencyOverride()
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
          <button
            onClick={sendEmergencyOverride}
            disabled={
              (emergencyType() !== 'screen-cover' && !alertText().trim()) || 
              commands.emergencyState().loading || 
              !isConnected()
            }
          >
            {commands.emergencyState().loading ? 'Sending...' : 'Send Emergency'}
          </button>
          
          <button
            onClick={clearEmergency}
            disabled={commands.emergencyState().loading || !isConnected()}
          >
            Clear
          </button>
        </div>
      </div>

      {/* Quick Emergency Actions */}
      <div>
        {quickEmergencies.map(emergency => (
          <button
            onClick={() => {
              setEmergencyType(emergency.type)
              setAlertText(emergency.text)
              setDuration(emergency.duration)
            }}
            disabled={commands.emergencyState().loading}
          >
            {emergency.type === 'screen-cover' ? 'Screen Cover' : emergency.text}
          </button>
        ))}
      </div>

      {/* Status Info */}
      <div>
        {commands.emergencyState().error && (
          <div>
            Error: {commands.emergencyState().error}
          </div>
        )}
        
        {commands.emergencyState().lastExecuted && (
          <div>
            Last executed: {new Date(commands.emergencyState().lastExecuted!).toLocaleTimeString()}
          </div>
        )}
        
        {lastSent() && (
          <div>
            Last: {lastSent()}
            <button
              onClick={replayLastAlert}
              disabled={commands.emergencyState().loading}
            >
              Replay
            </button>
          </div>
        )}
      </div>

      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div>
          <div>Emergency Loading: {commands.emergencyState().loading ? 'Yes' : 'No'}</div>
          <div>Emergency Error: {commands.emergencyState().error || 'None'}</div>
        </div>
      )}
    </div>
  )
}
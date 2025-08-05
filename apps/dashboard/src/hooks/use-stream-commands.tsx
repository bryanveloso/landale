/**
 * Clean command/query separation hook
 *
 * Provides command functions with proper loading states and error handling.
 * Separates commands from data subscriptions for clean architecture.
 */

import { createSignal } from 'solid-js'
import { useOverlayChannel, useQueueChannel } from './use-phoenix-channel'
import type { TakeoverCommand } from '@/types/stream'

interface CommandState {
  loading: boolean
  error: string | null
  lastExecuted: string | null
}

export function useStreamCommands() {
  const overlayChannel = useOverlayChannel()
  const queueChannel = useQueueChannel()

  // Command state tracking
  const [takeoverState, setTakeoverState] = createSignal<CommandState>({
    loading: false,
    error: null,
    lastExecuted: null
  })

  const [queueCommandState, setQueueCommandState] = createSignal<CommandState>({
    loading: false,
    error: null,
    lastExecuted: null
  })

  // Takeover commands
  const sendTakeover = async (command: TakeoverCommand) => {
    setTakeoverState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await overlayChannel.sendTakeover(command)
      setTakeoverState({
        loading: false,
        error: null,
        lastExecuted: new Date().toISOString()
      })
      return response
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      setTakeoverState({
        loading: false,
        error: errorMessage,
        lastExecuted: null
      })
      throw error
    }
  }

  const clearTakeover = async () => {
    setTakeoverState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await overlayChannel.clearTakeover()
      setTakeoverState({
        loading: false,
        error: null,
        lastExecuted: new Date().toISOString()
      })
      return response
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      setTakeoverState({
        loading: false,
        error: errorMessage,
        lastExecuted: null
      })
      throw error
    }
  }

  // Queue commands
  const removeQueueItem = async (id: string) => {
    setQueueCommandState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await queueChannel.removeQueueItem(id)
      setQueueCommandState({
        loading: false,
        error: null,
        lastExecuted: new Date().toISOString()
      })
      return response
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      setQueueCommandState({
        loading: false,
        error: errorMessage,
        lastExecuted: null
      })
      throw error
    }
  }

  // Utility commands
  const requestState = () => {
    // State is automatically requested by channels
  }

  const requestQueueState = () => {
    // Queue state is automatically requested by channels
  }

  const forceReconnect = () => {
    // This would be implemented at the Phoenix service level
  }

  return {
    // Commands
    sendTakeover,
    clearTakeover,
    removeQueueItem,

    // Command states
    takeoverState,
    queueCommandState,

    // Utilities
    requestState,
    requestQueueState,
    forceReconnect
  }
}

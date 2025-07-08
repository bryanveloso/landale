/**
 * Clean command/query separation hook
 * 
 * Provides command functions with proper loading states and error handling.
 * Separates commands from data subscriptions for clean architecture.
 */

import { createSignal } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import type { EmergencyOverrideCommand } from '@/types/stream'

interface CommandState {
  loading: boolean
  error: string | null
  lastExecuted: string | null
}

export function useStreamCommands() {
  const streamService = useStreamService()
  
  // Command state tracking
  const [emergencyState, setEmergencyState] = createSignal<CommandState>({
    loading: false,
    error: null,
    lastExecuted: null
  })
  
  const [queueCommandState, setQueueCommandState] = createSignal<CommandState>({
    loading: false,
    error: null,
    lastExecuted: null
  })

  // Emergency commands
  const sendEmergencyOverride = async (command: EmergencyOverrideCommand) => {
    setEmergencyState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await streamService.sendEmergencyOverride(command)
      setEmergencyState({
        loading: false,
        error: null,
        lastExecuted: new Date().toISOString()
      })
      return response
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      setEmergencyState({
        loading: false,
        error: errorMessage,
        lastExecuted: null
      })
      throw error
    }
  }

  const clearEmergency = async () => {
    setEmergencyState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await streamService.clearEmergency()
      setEmergencyState({
        loading: false,
        error: null,
        lastExecuted: new Date().toISOString()
      })
      return response
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      setEmergencyState({
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
      const response = await streamService.removeQueueItem(id)
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

  const clearQueue = async () => {
    setQueueCommandState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await streamService.clearQueue()
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

  const reorderQueue = async (id: string, position: number) => {
    setQueueCommandState({
      loading: true,
      error: null,
      lastExecuted: null
    })

    try {
      const response = await streamService.reorderQueue(id, position)
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

  // Utility functions
  const requestState = () => {
    streamService.requestState()
  }

  const requestQueueState = () => {
    streamService.requestQueueState()
  }

  return {
    // Emergency commands
    sendEmergencyOverride,
    clearEmergency,
    emergencyState,
    
    // Queue commands
    removeQueueItem,
    clearQueue,
    reorderQueue,
    queueCommandState,
    
    // Utility
    requestState,
    requestQueueState
  }
}
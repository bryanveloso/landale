import { useSubscription } from './use-subscription'
import type { OBSState } from '@landale/shared'

/**
 * OBS connection status hook
 * Subscribes to real-time connection updates from the server
 */
export function useOBSConnection() {
  const { data } = useSubscription<OBSState['connection']>('control.obs.onConnectionUpdate')
  return data
}

/**
 * OBS scenes hook
 * Manages scene list, current scene, and preview scene state
 */
export function useOBSScenes() {
  const { data: sceneState } = useSubscription<OBSState['scenes']>('control.obs.scenes.onScenesUpdate')

  return {
    scenes: sceneState,
    currentScene: sceneState?.current,
    previewScene: sceneState?.preview,
    sceneList: sceneState?.list || []
  }
}

/**
 * OBS streaming status hook
 * Tracks streaming state and statistics
 */
export function useOBSStreaming() {
  const { data } = useSubscription<OBSState['streaming']>('control.obs.streaming.onStreamingUpdate')
  return data
}

/**
 * OBS recording status hook
 * Tracks recording state and statistics
 */
export function useOBSRecording() {
  const { data } = useSubscription<OBSState['recording']>('control.obs.recording.onRecordingUpdate')
  return data
}

/**
 * OBS studio mode hook
 * Manages studio mode state
 */
export function useOBSStudioMode() {
  const { data } = useSubscription<OBSState['studioMode']>('control.obs.studioMode.onStudioModeUpdate')
  return data
}

/**
 * OBS virtual camera hook
 * Manages virtual camera state
 */
export function useOBSVirtualCam() {
  const { data } = useSubscription<OBSState['virtualCam']>('control.obs.virtualCam.onVirtualCamUpdate')
  return data
}

/**
 * OBS replay buffer hook
 * Manages replay buffer state
 */
export function useOBSReplayBuffer() {
  const { data } = useSubscription<OBSState['replayBuffer']>('control.obs.replayBuffer.onReplayBufferUpdate')
  return data
}

/**
 * Complete OBS state hook
 * Subscribes to all OBS state updates
 */
export function useOBSState() {
  const { data } = useSubscription<OBSState>('control.obs.onStateUpdate')
  return data
}
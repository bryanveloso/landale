// OBS State management types that extend obs-websocket-js types
// Uses types from obs-websocket-js package instead of redefining them

export interface OBSConnectionState {
  connected: boolean
  obsStudioVersion?: string
  obsWebSocketVersion?: string
  negotiatedRpcVersion?: number
  connectionState: 'disconnected' | 'connecting' | 'connected' | 'error'
  lastError?: string
  lastConnected?: Date
}

// OBS WebSocket scene object - flexible to match obs-websocket-js JsonObject
export interface OBSScene {
  sceneName?: string
  sceneIndex?: number
  sceneUuid?: string
  [key: string]: unknown // Matches JsonObject from obs-websocket-js
}

export interface OBSSceneState {
  current: string | null
  preview: string | null
  list: OBSScene[]
}

export interface OBSStreamingState {
  active: boolean
  reconnecting: boolean
  timecode: string
  duration: number
  congestion: number
  bytes: number
  skippedFrames: number
  totalFrames: number
}

export interface OBSRecordingState {
  active: boolean
  paused: boolean
  timecode: string
  duration: number
  bytes: number
  outputPath?: string
}

export interface OBSStudioModeState {
  enabled: boolean
}

export interface OBSStats {
  cpuUsage: number
  memoryUsage: number
  availableDiskSpace: number
  activeFps: number
  averageFrameRenderTime: number
  renderSkippedFrames: number
  renderTotalFrames: number
  outputSkippedFrames: number
  outputTotalFrames: number
}

// Main OBS state interface
export interface OBSState {
  connection: OBSConnectionState
  scenes: OBSSceneState
  streaming: OBSStreamingState
  recording: OBSRecordingState
  studioMode: OBSStudioModeState
  stats?: OBSStats
  virtualCam?: {
    active: boolean
  }
  replayBuffer?: {
    active: boolean
  }
}

// Action types for state updates
export type OBSStateAction =
  | { type: 'CONNECTION_CHANGED'; payload: Partial<OBSConnectionState> }
  | { type: 'SCENES_UPDATED'; payload: Partial<OBSSceneState> }
  | { type: 'STREAMING_CHANGED'; payload: Partial<OBSStreamingState> }
  | { type: 'RECORDING_CHANGED'; payload: Partial<OBSRecordingState> }
  | { type: 'STUDIO_MODE_CHANGED'; payload: Partial<OBSStudioModeState> }
  | { type: 'STATS_UPDATED'; payload: OBSStats }
  | { type: 'VIRTUAL_CAM_CHANGED'; payload: { active: boolean } }
  | { type: 'REPLAY_BUFFER_CHANGED'; payload: { active: boolean } }

// Common OBS control operations
export interface OBSControls {
  // Connection
  connect: () => Promise<void>
  disconnect: () => Promise<void>
  
  // Scenes
  setCurrentScene: (sceneName: string) => Promise<void>
  setPreviewScene: (sceneName: string) => Promise<void>
  createScene: (sceneName: string) => Promise<void>
  removeScene: (sceneName: string) => Promise<void>
  refreshScenes: () => Promise<void>
  
  // Streaming
  startStream: () => Promise<void>
  stopStream: () => Promise<void>
  
  // Recording
  startRecording: () => Promise<void>
  stopRecording: () => Promise<void>
  pauseRecording: () => Promise<void>
  resumeRecording: () => Promise<void>
  
  // Studio Mode
  enableStudioMode: () => Promise<void>
  disableStudioMode: () => Promise<void>
  triggerTransition: () => Promise<void>
  
  // Virtual Camera
  startVirtualCam: () => Promise<void>
  stopVirtualCam: () => Promise<void>
  
  // Replay Buffer
  startReplayBuffer: () => Promise<void>
  stopReplayBuffer: () => Promise<void>
  saveReplayBuffer: () => Promise<void>
}

// Configuration for OBS connection
export interface OBSConfig {
  url: string
  password?: string
  reconnectInterval?: number
  maxReconnectAttempts?: number
  eventSubscriptions?: number
}
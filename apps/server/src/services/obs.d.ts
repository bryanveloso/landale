import type { OBSState } from '@landale/shared'
declare class OBSService {
  private obs
  private state
  private reconnectTimer?
  private isConnecting
  private reconnectAttempts
  private maxReconnectAttempts
  private reconnectDelay
  private config
  constructor()
  private getInitialState
  private setupEventListeners
  private updateConnectionState
  private updateSceneState
  private updateStreamingState
  private updateRecordingState
  private updateStudioModeState
  private updateVirtualCamState
  private updateReplayBufferState
  private loadInitialState
  private scheduleReconnect
  connect(): Promise<void>
  disconnect(): Promise<void>
  setCurrentScene(sceneName: string): Promise<void>
  setPreviewScene(sceneName: string): Promise<void>
  createScene(sceneName: string): Promise<void>
  removeScene(sceneName: string): Promise<void>
  startStream(): Promise<void>
  stopStream(): Promise<void>
  startRecording(): Promise<void>
  stopRecording(): Promise<void>
  pauseRecording(): Promise<void>
  resumeRecording(): Promise<void>
  setStudioModeEnabled(enabled: boolean): Promise<void>
  triggerStudioModeTransition(): Promise<void>
  startVirtualCam(): Promise<void>
  stopVirtualCam(): Promise<void>
  startReplayBuffer(): Promise<void>
  stopReplayBuffer(): Promise<void>
  saveReplayBuffer(): Promise<void>
  getState(): OBSState
  isConnected(): boolean
  getVersion(): Promise<any>
  getStats(): Promise<any>
}
export declare const obsService: OBSService
export declare const initialize: () => Promise<void>
export declare const shutdown: () => Promise<void>
export {}
//# sourceMappingURL=obs.d.ts.map

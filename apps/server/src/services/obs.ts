import { OBSWebSocket, EventSubscription } from '@omnypro/obs-websocket'
import { createLogger } from '@landale/logger'
import { eventEmitter } from '@/events'
import type { OBSState } from '@landale/shared'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'obs' })

class OBSService {
  private obs: OBSWebSocket
  private state: OBSState
  private reconnectTimer?: NodeJS.Timeout
  private isConnecting = false
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5
  private reconnectDelay = 5000

  // OBS connection configuration
  private config = {
    url: process.env.OBS_WEBSOCKET_URL || 'ws://192.168.1.9:4455',
    password: process.env.OBS_WEBSOCKET_PASSWORD || '', // yfX1E3UyKP3gTQ2e
    eventSubscriptions: EventSubscription.All
  }

  constructor() {
    this.obs = new OBSWebSocket()
    this.state = this.getInitialState()
    this.setupEventListeners()
  }

  private getInitialState(): OBSState {
    return {
      connection: {
        connected: false,
        connectionState: 'disconnected'
      },
      scenes: {
        current: null,
        preview: null,
        list: []
      },
      streaming: {
        active: false,
        reconnecting: false,
        timecode: '00:00:00',
        duration: 0,
        congestion: 0,
        bytes: 0,
        skippedFrames: 0,
        totalFrames: 0
      },
      recording: {
        active: false,
        paused: false,
        timecode: '00:00:00',
        duration: 0,
        bytes: 0
      },
      studioMode: {
        enabled: false
      }
    }
  }

  private setupEventListeners() {
    // Connection events
    this.obs.on('ConnectionOpened', () => {
      log.info('OBS WebSocket connection opened')
      log.debug('Current state after open', { connection: this.state.connection })
    })

    this.obs.on('Identified', async (data) => {
      log.info('OBS connected', { rpcVersion: data.negotiatedRpcVersion })
      this.updateConnectionState({
        connected: true,
        connectionState: 'connected',
        negotiatedRpcVersion: data.negotiatedRpcVersion,
        lastConnected: new Date()
      })
      this.reconnectAttempts = 0

      // Load initial state after successful connection
      await this.loadInitialState()
    })

    this.obs.on('ConnectionClosed', () => {
      log.warn('OBS WebSocket connection closed')
      this.updateConnectionState({
        connected: false,
        connectionState: 'disconnected'
      })
      this.scheduleReconnect()
    })

    this.obs.on('ConnectionError', (error) => {
      log.error('OBS WebSocket connection error', { error })
      this.updateConnectionState({
        connected: false,
        connectionState: 'error',
        lastError: error.message
      })
      this.scheduleReconnect()
    })

    // Scene events - these map directly to OBS WebSocket event names
    this.obs.on('CurrentProgramSceneChanged', (data) => {
      log.debug('Current program scene changed', { sceneName: data.sceneName })
      this.updateSceneState({ current: data.sceneName })
      eventEmitter.emit('obs:scene:current-changed', data)
    })

    this.obs.on('CurrentPreviewSceneChanged', (data) => {
      log.debug('Current preview scene changed', { sceneName: data.sceneName })
      this.updateSceneState({ preview: data.sceneName })
      eventEmitter.emit('obs:scene:preview-changed', data)
    })

    this.obs.on('SceneListChanged', (data) => {
      log.debug('Scene list changed', { sceneCount: data.scenes.length })
      this.updateSceneState({ list: data.scenes })
      eventEmitter.emit('obs:scene:list-changed', data)
    })

    // Streaming events
    this.obs.on('StreamStateChanged', (data) => {
      log.info('Stream state changed', { 
        outputState: data.outputState, 
        outputActive: data.outputActive 
      })
      this.updateStreamingState({ active: data.outputActive })
      eventEmitter.emit('obs:stream:state-changed', data)
    })

    // Recording events
    this.obs.on('RecordStateChanged', (data) => {
      log.info('Record state changed', { 
        outputState: data.outputState, 
        outputActive: data.outputActive 
      })
      this.updateRecordingState({
        active: data.outputActive,
        paused: 'outputPaused' in data ? Boolean(data.outputPaused) : false
      })
      eventEmitter.emit('obs:record:state-changed', data)
    })

    // Studio mode events
    this.obs.on('StudioModeStateChanged', (data) => {
      log.info('Studio mode changed', { studioModeEnabled: data.studioModeEnabled })
      this.updateStudioModeState({ enabled: data.studioModeEnabled })
      eventEmitter.emit('obs:studio-mode:changed', data)
    })

    // Virtual camera events
    this.obs.on('VirtualcamStateChanged', (data) => {
      log.info('Virtual camera state changed', { outputActive: data.outputActive })
      this.updateVirtualCamState({ active: data.outputActive })
      eventEmitter.emit('obs:virtual-cam:changed', data)
    })

    // Replay buffer events
    this.obs.on('ReplayBufferStateChanged', (data) => {
      log.info('Replay buffer state changed', { outputActive: data.outputActive })
      this.updateReplayBufferState({ active: data.outputActive })
      eventEmitter.emit('obs:replay-buffer:changed', data)
    })

    // Error handling for requests
    this.obs.on('ConnectionError', (error) => {
      log.error('OBS request error', { error })
    })
  }

  private updateConnectionState(update: Partial<OBSState['connection']>) {
    this.state.connection = { ...this.state.connection, ...update }
    log.debug('Updating connection state', { connection: this.state.connection })
    eventEmitter.emit('obs:connection:changed', this.state.connection)
  }

  private updateSceneState(update: Partial<OBSState['scenes']>) {
    this.state.scenes = { ...this.state.scenes, ...update }
    eventEmitter.emit('obs:scenes:updated', this.state.scenes)
  }

  private updateStreamingState(update: Partial<OBSState['streaming']>) {
    this.state.streaming = { ...this.state.streaming, ...update }
    eventEmitter.emit('obs:streaming:updated', this.state.streaming)
  }

  private updateRecordingState(update: Partial<OBSState['recording']>) {
    this.state.recording = { ...this.state.recording, ...update }
    eventEmitter.emit('obs:recording:updated', this.state.recording)
  }

  private updateStudioModeState(update: Partial<OBSState['studioMode']>) {
    this.state.studioMode = { ...this.state.studioMode, ...update }
    eventEmitter.emit('obs:studio-mode:updated', this.state.studioMode)
  }

  private updateVirtualCamState(update: { active: boolean }) {
    this.state.virtualCam = update
    eventEmitter.emit('obs:virtual-cam:updated', this.state.virtualCam)
  }

  private updateReplayBufferState(update: { active: boolean }) {
    this.state.replayBuffer = update
    eventEmitter.emit('obs:replay-buffer:updated', this.state.replayBuffer)
  }

  private async loadInitialState() {
    try {
      // Get scene list and current scenes
      const sceneList = await this.obs.call('GetSceneList')
      this.updateSceneState({
        current: sceneList.currentProgramSceneName,
        preview: sceneList.currentPreviewSceneName,
        list: sceneList.scenes
      })

      // Get streaming status
      try {
        const streamStatus = await this.obs.call('GetStreamStatus')
        this.updateStreamingState({
          active: streamStatus.outputActive,
          timecode: streamStatus.outputTimecode || '00:00:00',
          duration: streamStatus.outputDuration || 0,
          congestion: streamStatus.outputCongestion || 0,
          bytes: streamStatus.outputBytes || 0,
          skippedFrames: streamStatus.outputSkippedFrames || 0,
          totalFrames: streamStatus.outputTotalFrames || 0
        })
      } catch (error) {
        log.warn('Failed to get stream status', { error })
      }

      // Get recording status
      try {
        const recordStatus = await this.obs.call('GetRecordStatus')
        this.updateRecordingState({
          active: recordStatus.outputActive,
          paused: recordStatus.outputPaused || false,
          timecode: recordStatus.outputTimecode || '00:00:00',
          duration: recordStatus.outputDuration || 0,
          bytes: recordStatus.outputBytes || 0
        })
      } catch (error) {
        log.warn('Failed to get record status', { error })
      }

      // Get studio mode status
      try {
        const studioMode = await this.obs.call('GetStudioModeEnabled')
        this.updateStudioModeState({ enabled: studioMode.studioModeEnabled })
      } catch (error) {
        log.warn('Failed to get studio mode status', { error })
      }

      // Get virtual cam status
      try {
        const virtualCamStatus = await this.obs.call('GetVirtualCamStatus')
        this.updateVirtualCamState({ active: virtualCamStatus.outputActive })
      } catch (error) {
        log.warn('Failed to get virtual cam status', { error })
      }

      // Get replay buffer status
      try {
        const replayBufferStatus = await this.obs.call('GetReplayBufferStatus')
        this.updateReplayBufferState({ active: replayBufferStatus.outputActive })
      } catch (error) {
        log.warn('Failed to get replay buffer status', { error })
      }

      log.info('Initial OBS state loaded successfully')
    } catch (error) {
      log.error('Failed to load initial OBS state', { error })
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer || this.reconnectAttempts >= this.maxReconnectAttempts) {
      if (this.reconnectAttempts >= this.maxReconnectAttempts) {
        log.error('Max reconnection attempts reached. Giving up', { 
          maxAttempts: this.maxReconnectAttempts 
        })
      }
      return
    }

    this.reconnectAttempts++
    const delay = this.reconnectDelay * Math.min(this.reconnectAttempts, 5) // Exponential backoff with cap

    log.info('Scheduling OBS reconnection', { 
      attempt: this.reconnectAttempts, 
      maxAttempts: this.maxReconnectAttempts, 
      delayMs: delay 
    })

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined
      this.connect()
    }, delay)
  }

  // Public methods
  async connect() {
    if (this.isConnecting || this.obs.connected) {
      return
    }

    this.isConnecting = true
    this.updateConnectionState({ connectionState: 'connecting' })

    try {
      log.info('Connecting to OBS', { url: this.config.url })
      // Pass undefined for password when auth is disabled
      const password = this.config.password || undefined
      log.debug('Using password authentication', { hasPassword: !!password })
      await this.obs.connect(this.config.url, password)
    } catch (error) {
      log.error('Failed to connect to OBS', { error })
      this.updateConnectionState({
        connected: false,
        connectionState: 'error',
        lastError: error instanceof Error ? error.message : String(error)
      })
      this.scheduleReconnect()
    } finally {
      this.isConnecting = false
    }
  }

  async disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = undefined
    }

    if (this.obs.connected) {
      await this.obs.disconnect()
    }
  }

  // Scene controls
  async setCurrentScene(sceneName: string) {
    await this.obs.call('SetCurrentProgramScene', { sceneName })
  }

  async setPreviewScene(sceneName: string) {
    await this.obs.call('SetCurrentPreviewScene', { sceneName })
  }

  async createScene(sceneName: string) {
    await this.obs.call('CreateScene', { sceneName })
  }

  async removeScene(sceneName: string) {
    await this.obs.call('RemoveScene', { sceneName })
  }

  // Streaming controls
  async startStream() {
    await this.obs.call('StartStream')
  }

  async stopStream() {
    await this.obs.call('StopStream')
  }

  // Recording controls
  async startRecording() {
    await this.obs.call('StartRecord')
  }

  async stopRecording() {
    await this.obs.call('StopRecord')
  }

  async pauseRecording() {
    await this.obs.call('PauseRecord')
  }

  async resumeRecording() {
    await this.obs.call('ResumeRecord')
  }

  // Studio mode controls
  async setStudioModeEnabled(enabled: boolean) {
    await this.obs.call('SetStudioModeEnabled', { studioModeEnabled: enabled })
  }

  async triggerStudioModeTransition() {
    await this.obs.call('TriggerStudioModeTransition')
  }

  // Virtual camera controls
  async startVirtualCam() {
    await this.obs.call('StartVirtualCam')
  }

  async stopVirtualCam() {
    await this.obs.call('StopVirtualCam')
  }

  // Replay buffer controls
  async startReplayBuffer() {
    await this.obs.call('StartReplayBuffer')
  }

  async stopReplayBuffer() {
    await this.obs.call('StopReplayBuffer')
  }

  async saveReplayBuffer() {
    await this.obs.call('SaveReplayBuffer')
  }

  // Getters
  getState(): OBSState {
    return this.state
  }

  isConnected(): boolean {
    return this.state.connection.connected
  }

  // For debugging
  async getVersion() {
    return await this.obs.call('GetVersion')
  }

  async getStats() {
    return await this.obs.call('GetStats')
  }
}

// Create singleton instance
export const obsService = new OBSService()

// Match IronMON and Twitch signature patterns
export const initialize = async () => {
  log.info('Initializing OBS service')
  await obsService.connect()
}

export const shutdown = async () => {
  log.info('Shutting down OBS service')
  await obsService.disconnect()
}

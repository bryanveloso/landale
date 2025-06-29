import { OBSWebSocket, EventSubscription } from '@omnypro/obs-websocket'
import { createLogger } from '@landale/logger'
import { services } from '@landale/service-config'
import { eventEmitter } from '@/events'
import { performanceMonitor, trackApiCall, type StreamHealthMetric } from '@/lib/performance'
import { auditLogger, AuditAction, AuditCategory } from '@/lib/audit'
import type { OBSState } from '@landale/shared'

// Type definitions for OBS WebSocket responses
interface GetSceneListResponse {
  currentProgramSceneName: string
  currentPreviewSceneName?: string
  scenes: Array<{ sceneName?: string; sceneIndex?: number; sceneUuid?: string }>
}

interface GetStreamStatusResponse {
  outputActive: boolean
  outputTimecode?: string
  outputDuration?: number
  outputCongestion?: number
  outputBytes?: number
  outputSkippedFrames?: number
  outputTotalFrames?: number
}

interface GetRecordStatusResponse {
  outputActive: boolean
  outputPaused?: boolean
  outputTimecode?: string
  outputDuration?: number
  outputBytes?: number
}

interface GetStudioModeEnabledResponse {
  studioModeEnabled: boolean
}

interface GetVirtualCamStatusResponse {
  outputActive: boolean
}

interface GetReplayBufferStatusResponse {
  outputActive: boolean
}

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
    url: process.env.OBS_WEBSOCKET_URL || services.getWebSocketUrl('obs'),
    password: process.env.OBS_WEBSOCKET_PASSWORD || '',
    eventSubscriptions: EventSubscription.All
  }

  // Performance tracking
  private statsPollingInterval?: NodeJS.Timeout
  private readonly STATS_POLLING_INTERVAL = 5000 // 5 seconds

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
      log.debug('Current state after open', { metadata: { connection: this.state.connection } })
    })

    this.obs.on('Identified', async (data: { negotiatedRpcVersion: number }) => {
      log.info('OBS connected', { metadata: { rpcVersion: data.negotiatedRpcVersion } })
      this.updateConnectionState({
        connected: true,
        connectionState: 'connected',
        negotiatedRpcVersion: data.negotiatedRpcVersion,
        lastConnected: new Date()
      })
      this.reconnectAttempts = 0

      // Log connection established
      await auditLogger.logConnectionEvent('OBS', AuditAction.CONNECTION_ESTABLISHED, {
        url: this.config.url,
        rpcVersion: data.negotiatedRpcVersion
      })

      // Load initial state after successful connection
      await this.loadInitialState()

      // Start performance monitoring
      this.startStatsPolling()
    })

    this.obs.on('ConnectionClosed', () => {
      log.warn('OBS WebSocket connection closed')
      this.updateConnectionState({
        connected: false,
        connectionState: 'disconnected'
      })

      // Stop performance monitoring
      this.stopStatsPolling()

      // Log connection lost
      void auditLogger.logConnectionEvent('OBS', AuditAction.CONNECTION_LOST)

      this.scheduleReconnect()
    })

    this.obs.on('ConnectionError', (error: Error) => {
      log.error('OBS WebSocket connection error', { error })
      this.updateConnectionState({
        connected: false,
        connectionState: 'error',
        lastError: error.message
      })

      // Log connection failure
      void auditLogger.logConnectionEvent('OBS', AuditAction.CONNECTION_FAILED, undefined, error.message)

      this.scheduleReconnect()
    })

    // Scene events - these map directly to OBS WebSocket event names
    this.obs.on('CurrentProgramSceneChanged', (data: { sceneName: string; sceneUuid?: string }) => {
      log.debug('Current program scene changed', { metadata: { sceneName: data.sceneName } })
      const previousScene = this.state.scenes.current
      this.updateSceneState({ current: data.sceneName })

      // Audit log scene change
      void auditLogger.logSceneChange(previousScene, data.sceneName)

      void eventEmitter.emit('obs:scene:current-changed', data)
    })

    this.obs.on('CurrentPreviewSceneChanged', (data: { sceneName: string; sceneUuid?: string }) => {
      log.debug('Current preview scene changed', { metadata: { sceneName: data.sceneName } })
      this.updateSceneState({ preview: data.sceneName })
      void eventEmitter.emit('obs:scene:preview-changed', data)
    })

    this.obs.on(
      'SceneListChanged',
      (data: { scenes: Array<{ sceneName?: string; sceneIndex?: number; sceneUuid?: string }> }) => {
        log.debug('Scene list changed', { metadata: { sceneCount: data.scenes.length } })
        this.updateSceneState({ list: data.scenes })
        void eventEmitter.emit('obs:scene:list-changed', data)
      }
    )

    // Streaming events
    this.obs.on('StreamStateChanged', (data: { outputActive: boolean; outputState: string }) => {
      log.info('Stream state changed', {
        metadata: { outputState: data.outputState, outputActive: data.outputActive }
      })
      this.updateStreamingState({ active: data.outputActive })

      // Audit log stream state changes
      if (data.outputActive) {
        void auditLogger.logStreamStart(undefined, { outputState: data.outputState })
      } else {
        void auditLogger.logStreamStop(undefined, { outputState: data.outputState })
      }

      void eventEmitter.emit('obs:stream:state-changed', data)
    })

    // Recording events
    this.obs.on(
      'RecordStateChanged',
      (data: { outputActive: boolean; outputState: string; outputPaused?: boolean }) => {
        log.info('Record state changed', {
          metadata: { outputState: data.outputState, outputActive: data.outputActive }
        })
        this.updateRecordingState({
          active: data.outputActive,
          paused: 'outputPaused' in data ? Boolean(data.outputPaused) : false
        })

        // Audit log recording state changes
        if (data.outputActive && !this.state.recording.active) {
          void auditLogger.log({
            action: AuditAction.RECORDING_START,
            category: AuditCategory.RECORDING,
            result: 'success',
            metadata: { outputState: data.outputState }
          })
        } else if (!data.outputActive && this.state.recording.active) {
          void auditLogger.log({
            action: AuditAction.RECORDING_STOP,
            category: AuditCategory.RECORDING,
            result: 'success',
            metadata: { outputState: data.outputState }
          })
        }

        void eventEmitter.emit('obs:record:state-changed', data)
      }
    )

    // Studio mode events
    this.obs.on('StudioModeStateChanged', (data: { studioModeEnabled: boolean }) => {
      log.info('Studio mode changed', { metadata: { studioModeEnabled: data.studioModeEnabled } })
      this.updateStudioModeState({ enabled: data.studioModeEnabled })
      void eventEmitter.emit('obs:studio-mode:changed', data)
    })

    // Virtual camera events
    this.obs.on('VirtualcamStateChanged', (data: { outputActive: boolean; outputState: string }) => {
      log.info('Virtual camera state changed', { metadata: { outputActive: data.outputActive } })
      this.updateVirtualCamState({ active: data.outputActive })
      void eventEmitter.emit('obs:virtual-cam:changed', data)
    })

    // Replay buffer events
    this.obs.on('ReplayBufferStateChanged', (data: { outputActive: boolean; outputState: string }) => {
      log.info('Replay buffer state changed', { metadata: { outputActive: data.outputActive } })
      this.updateReplayBufferState({ active: data.outputActive })
      void eventEmitter.emit('obs:replay-buffer:changed', data)
    })

    // Error handling for requests
    this.obs.on('ConnectionError', (error: Error) => {
      log.error('OBS request error', { error })
    })
  }

  private updateConnectionState(update: Partial<OBSState['connection']>) {
    this.state.connection = { ...this.state.connection, ...update }
    log.debug('Updating connection state', { metadata: { connection: this.state.connection } })
    void eventEmitter.emit('obs:connection:changed', this.state.connection)
  }

  private updateSceneState(update: Partial<OBSState['scenes']>) {
    this.state.scenes = { ...this.state.scenes, ...update }
    void eventEmitter.emit('obs:scenes:updated', this.state.scenes)
  }

  private updateStreamingState(update: Partial<OBSState['streaming']>) {
    this.state.streaming = { ...this.state.streaming, ...update }
    void eventEmitter.emit('obs:streaming:updated', this.state.streaming)
  }

  private updateRecordingState(update: Partial<OBSState['recording']>) {
    this.state.recording = { ...this.state.recording, ...update }
    void eventEmitter.emit('obs:recording:updated', this.state.recording)
  }

  private updateStudioModeState(update: Partial<OBSState['studioMode']>) {
    this.state.studioMode = { ...this.state.studioMode, ...update }
    void eventEmitter.emit('obs:studio-mode:updated', this.state.studioMode)
  }

  private updateVirtualCamState(update: { active: boolean }) {
    this.state.virtualCam = update
    void eventEmitter.emit('obs:virtual-cam:updated', this.state.virtualCam)
  }

  private updateReplayBufferState(update: { active: boolean }) {
    this.state.replayBuffer = update
    void eventEmitter.emit('obs:replay-buffer:updated', this.state.replayBuffer)
  }

  private async loadInitialState() {
    try {
      // Get scene list and current scenes
      const sceneList = await this.obs.call<GetSceneListResponse>('GetSceneList')
      this.updateSceneState({
        current: sceneList.currentProgramSceneName,
        preview: sceneList.currentPreviewSceneName,
        list: sceneList.scenes
      })

      // Get streaming status
      try {
        const streamStatus = await this.obs.call<GetStreamStatusResponse>('GetStreamStatus')
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
        log.warn('Failed to get stream status', { error: error as Error })
      }

      // Get recording status
      try {
        const recordStatus = await this.obs.call<GetRecordStatusResponse>('GetRecordStatus')
        this.updateRecordingState({
          active: recordStatus.outputActive,
          paused: recordStatus.outputPaused || false,
          timecode: recordStatus.outputTimecode || '00:00:00',
          duration: recordStatus.outputDuration || 0,
          bytes: recordStatus.outputBytes || 0
        })
      } catch (error) {
        log.warn('Failed to get record status', { error: error as Error })
      }

      // Get studio mode status
      try {
        const studioMode = await this.obs.call<GetStudioModeEnabledResponse>('GetStudioModeEnabled')
        this.updateStudioModeState({ enabled: studioMode.studioModeEnabled })
      } catch (error) {
        log.warn('Failed to get studio mode status', { error: error as Error })
      }

      // Get virtual cam status
      try {
        const virtualCamStatus = await this.obs.call<GetVirtualCamStatusResponse>('GetVirtualCamStatus')
        this.updateVirtualCamState({ active: virtualCamStatus.outputActive })
      } catch (error) {
        log.warn('Failed to get virtual cam status', { error: error as Error })
      }

      // Get replay buffer status
      try {
        const replayBufferStatus = await this.obs.call<GetReplayBufferStatusResponse>('GetReplayBufferStatus')
        this.updateReplayBufferState({ active: replayBufferStatus.outputActive })
      } catch (error) {
        log.warn('Failed to get replay buffer status', { error: error as Error })
      }

      log.info('Initial OBS state loaded successfully')
    } catch (error) {
      log.error('Failed to load initial OBS state', { error: error as Error })
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer || this.reconnectAttempts >= this.maxReconnectAttempts) {
      if (this.reconnectAttempts >= this.maxReconnectAttempts) {
        log.error('Max reconnection attempts reached. Giving up', {
          metadata: { maxAttempts: this.maxReconnectAttempts }
        })
      }
      return
    }

    this.reconnectAttempts++
    const delay = this.reconnectDelay * Math.min(this.reconnectAttempts, 5) // Exponential backoff with cap

    log.info('Scheduling OBS reconnection', {
      metadata: { attempt: this.reconnectAttempts, maxAttempts: this.maxReconnectAttempts, delayMs: delay }
    })

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined
      void this.connect()
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
      log.info('Connecting to OBS', { metadata: { url: this.config.url } })
      // Pass undefined for password when auth is disabled
      const password = this.config.password || undefined
      log.debug('Using password authentication', { metadata: { hasPassword: !!password } })
      await this.obs.connect(this.config.url, password)
    } catch (error) {
      log.error('Failed to connect to OBS', { error: error as Error })
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

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = undefined
    }

    if (this.obs.connected) {
      this.obs.disconnect()
    }
  }

  // Performance monitoring
  startStatsPolling() {
    this.stopStatsPolling() // Ensure no duplicate intervals

    this.statsPollingInterval = setInterval(() => {
      void (async () => {
        if (!this.isConnected()) return

        try {
          const stats = await this.getStats()

          const healthMetric: StreamHealthMetric = {
            fps: stats.activeFps,
            bitrate: 0, // OBS doesn't provide bitrate directly
            droppedFrames: stats.outputSkippedFrames,
            totalFrames: stats.outputTotalFrames,
            cpuUsage: stats.cpuUsage,
            memoryUsage: stats.memoryUsage,
            congestion: this.state.streaming.congestion,
            timestamp: new Date()
          }

          performanceMonitor.trackStreamHealth(healthMetric)
        } catch (error) {
          log.debug('Failed to get OBS stats', { error: error as Error })

          // Emit error state metric so dashboard knows stats are unavailable
          performanceMonitor.trackStreamHealth({
            fps: 0,
            bitrate: 0,
            droppedFrames: 0,
            totalFrames: 0,
            cpuUsage: 0,
            memoryUsage: 0,
            congestion: 0,
            timestamp: new Date()
          })
        }
      })()
    }, this.STATS_POLLING_INTERVAL)
  }

  stopStatsPolling() {
    if (this.statsPollingInterval) {
      clearInterval(this.statsPollingInterval)
      this.statsPollingInterval = undefined
    }
  }

  // Scene controls with performance tracking
  async setCurrentScene(sceneName: string, correlationId?: string) {
    if (!this.isConnected()) {
      throw new Error('OBS is not connected')
    }
    await trackApiCall(
      'obs',
      'setCurrentScene',
      async () => {
        await this.obs.call('SetCurrentProgramScene', { sceneName })
      },
      { sceneName, correlationId }
    )
  }

  async setPreviewScene(sceneName: string, correlationId?: string) {
    if (!this.isConnected()) {
      throw new Error('OBS is not connected')
    }
    await trackApiCall(
      'obs',
      'setPreviewScene',
      async () => {
        await this.obs.call('SetCurrentPreviewScene', { sceneName })
      },
      { sceneName, correlationId }
    )
  }

  async createScene(sceneName: string, correlationId?: string) {
    await trackApiCall(
      'obs',
      'createScene',
      async () => {
        await this.obs.call('CreateScene', { sceneName })
      },
      { sceneName, correlationId }
    )
  }

  async removeScene(sceneName: string, correlationId?: string) {
    await trackApiCall(
      'obs',
      'removeScene',
      async () => {
        await this.obs.call('RemoveScene', { sceneName })
      },
      { sceneName, correlationId }
    )
  }

  // Streaming controls
  async startStream(correlationId?: string) {
    if (!this.isConnected()) {
      throw new Error('OBS is not connected')
    }
    await trackApiCall(
      'obs',
      'startStream',
      async () => {
        await this.obs.call('StartStream')
      },
      { correlationId }
    )
  }

  async stopStream(correlationId?: string) {
    if (!this.isConnected()) {
      throw new Error('OBS is not connected')
    }
    await trackApiCall(
      'obs',
      'stopStream',
      async () => {
        await this.obs.call('StopStream')
      },
      { correlationId }
    )
  }

  // Recording controls
  async startRecording(correlationId?: string) {
    await trackApiCall(
      'obs',
      'startRecording',
      async () => {
        await this.obs.call('StartRecord')
      },
      { correlationId }
    )
  }

  async stopRecording(correlationId?: string) {
    await trackApiCall(
      'obs',
      'stopRecording',
      async () => {
        await this.obs.call('StopRecord')
      },
      { correlationId }
    )
  }

  async pauseRecording(correlationId?: string) {
    await trackApiCall(
      'obs',
      'pauseRecording',
      async () => {
        await this.obs.call('PauseRecord')
      },
      { correlationId }
    )
  }

  async resumeRecording(correlationId?: string) {
    await trackApiCall(
      'obs',
      'resumeRecording',
      async () => {
        await this.obs.call('ResumeRecord')
      },
      { correlationId }
    )
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
  async getVersion(): Promise<{
    obsVersion: string
    obsWebSocketVersion: string
    rpcVersion: number
    availableRequests: string[]
  }> {
    return await this.obs.call('GetVersion')
  }

  async getStats(): Promise<{
    cpuUsage: number
    memoryUsage: number
    availableDiskSpace: number
    activeFps: number
    averageFrameRenderTime: number
    renderSkippedFrames: number
    renderTotalFrames: number
    outputSkippedFrames: number
    outputTotalFrames: number
  }> {
    return await this.obs.call('GetStats')
  }
}

// Create singleton instance
export const obsService = new OBSService()

// Export getter for health checks
export function getOBSService(): OBSService {
  return obsService
}

// Match IronMON and Twitch signature patterns
export const initialize = async () => {
  log.info('Initializing OBS service')
  await obsService.connect()
}

export const shutdown = () => {
  log.info('Shutting down OBS service')
  obsService.stopStatsPolling()
  obsService.disconnect()
}

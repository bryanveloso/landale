import { 
  useOBSConnection, 
  useOBSScenes, 
  useOBSStreaming, 
  useOBSRecording,
  useOBSStudioMode,
  useOBSVirtualCam,
  useOBSReplayBuffer
} from '@/hooks/use-obs'
import { useOBSControls } from '@/hooks/use-obs-controls'

function ConnectionStatus() {
  const connection = useOBSConnection()

  if (!connection) {
    return (
      <div className="flex items-center gap-2 rounded-lg bg-gray-100 px-3 py-2">
        <div className="h-3 w-3 rounded-full bg-gray-400"></div>
        <span className="text-sm text-gray-600">Loading...</span>
      </div>
    )
  }

  const isConnected = connection.connected
  const statusColor = isConnected ? 'bg-green-500' : 'bg-red-500'
  const statusText = isConnected ? 'Connected' : 'Disconnected'

  return (
    <div className="flex items-center gap-2 rounded-lg bg-gray-100 px-3 py-2">
      <div className={`h-3 w-3 rounded-full ${statusColor}`}></div>
      <span className="text-sm font-medium">{statusText}</span>
      {connection.obsStudioVersion && (
        <span className="text-xs text-gray-500">OBS {connection.obsStudioVersion}</span>
      )}
    </div>
  )
}

function SceneControls() {
  const { currentScene, previewScene, sceneList } = useOBSScenes()
  const controls = useOBSControls()

  return (
    <div className="rounded-lg border bg-white p-4">
      <h3 className="mb-4 text-lg font-semibold">Scenes</h3>
      
      <div className="mb-4 grid grid-cols-2 gap-4 text-sm">
        <div>
          <span className="font-medium">Current:</span>{' '}
          <span className="rounded bg-red-100 px-2 py-1 text-red-800">
            {currentScene || 'None'}
          </span>
        </div>
        <div>
          <span className="font-medium">Preview:</span>{' '}
          <span className="rounded bg-blue-100 px-2 py-1 text-blue-800">
            {previewScene || 'None'}
          </span>
        </div>
      </div>

      <div className="space-y-2">
        <h4 className="font-medium">Scene List</h4>
        <div className="grid grid-cols-2 gap-2">
          {sceneList.map((scene) => (
            <div key={scene.sceneUuid || scene.sceneName} className="flex gap-2">
              <button
                onClick={() => controls.scenes.setCurrentScene(scene.sceneName || '')}
                className="flex-1 rounded bg-red-500 px-3 py-2 text-xs text-white hover:bg-red-600"
                title="Set as current scene"
              >
                🔴 {scene.sceneName}
              </button>
              <button
                onClick={() => controls.scenes.setPreviewScene(scene.sceneName || '')}
                className="flex-1 rounded bg-blue-500 px-3 py-2 text-xs text-white hover:bg-blue-600"
                title="Set as preview scene"
              >
                👁️ {scene.sceneName}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function StreamingControls() {
  const streaming = useOBSStreaming()
  const controls = useOBSControls()

  const isStreaming = streaming?.active || false

  return (
    <div className="rounded-lg border bg-white p-4">
      <h3 className="mb-4 text-lg font-semibold">Streaming</h3>
      
      <div className="mb-4">
        <div className="flex items-center gap-2">
          <div className={`h-3 w-3 rounded-full ${isStreaming ? 'bg-red-500' : 'bg-gray-400'}`}></div>
          <span className="font-medium">{isStreaming ? 'LIVE' : 'Offline'}</span>
        </div>
        {streaming && isStreaming && (
          <div className="mt-2 text-sm text-gray-600">
            <div>Duration: {streaming.timecode}</div>
            <div>Bytes: {streaming.bytes.toLocaleString()}</div>
            {streaming.skippedFrames > 0 && (
              <div className="text-yellow-600">
                Dropped: {streaming.skippedFrames}/{streaming.totalFrames} frames
              </div>
            )}
          </div>
        )}
      </div>

      <div className="flex gap-2">
        <button
          onClick={controls.streaming.startStream}
          disabled={isStreaming}
          className="flex-1 rounded bg-red-500 px-4 py-2 text-white hover:bg-red-600 disabled:bg-gray-400"
        >
          🔴 Start Stream
        </button>
        <button
          onClick={controls.streaming.stopStream}
          disabled={!isStreaming}
          className="flex-1 rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600 disabled:bg-gray-400"
        >
          ⏹️ Stop Stream
        </button>
      </div>
    </div>
  )
}

function RecordingControls() {
  const recording = useOBSRecording()
  const controls = useOBSControls()

  const isRecording = recording?.active || false
  const isPaused = recording?.paused || false

  return (
    <div className="rounded-lg border bg-white p-4">
      <h3 className="mb-4 text-lg font-semibold">Recording</h3>
      
      <div className="mb-4">
        <div className="flex items-center gap-2">
          <div className={`h-3 w-3 rounded-full ${
            isRecording ? (isPaused ? 'bg-yellow-500' : 'bg-red-500') : 'bg-gray-400'
          }`}></div>
          <span className="font-medium">
            {isRecording ? (isPaused ? 'Paused' : 'Recording') : 'Stopped'}
          </span>
        </div>
        {recording && isRecording && (
          <div className="mt-2 text-sm text-gray-600">
            <div>Duration: {recording.timecode}</div>
            <div>Size: {recording.bytes.toLocaleString()} bytes</div>
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2">
        <button
          onClick={controls.recording.startRecording}
          disabled={isRecording}
          className="rounded bg-red-500 px-4 py-2 text-white hover:bg-red-600 disabled:bg-gray-400"
        >
          🔴 Start
        </button>
        <button
          onClick={controls.recording.stopRecording}
          disabled={!isRecording}
          className="rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600 disabled:bg-gray-400"
        >
          ⏹️ Stop
        </button>
        <button
          onClick={controls.recording.pauseRecording}
          disabled={!isRecording || isPaused}
          className="rounded bg-yellow-500 px-4 py-2 text-white hover:bg-yellow-600 disabled:bg-gray-400"
        >
          ⏸️ Pause
        </button>
        <button
          onClick={controls.recording.resumeRecording}
          disabled={!isRecording || !isPaused}
          className="rounded bg-green-500 px-4 py-2 text-white hover:bg-green-600 disabled:bg-gray-400"
        >
          ▶️ Resume
        </button>
      </div>
    </div>
  )
}

function StudioModeControls() {
  const studioMode = useOBSStudioMode()
  const controls = useOBSControls()

  const isEnabled = studioMode?.enabled || false

  return (
    <div className="rounded-lg border bg-white p-4">
      <h3 className="mb-4 text-lg font-semibold">Studio Mode</h3>
      
      <div className="mb-4">
        <div className="flex items-center gap-2">
          <div className={`h-3 w-3 rounded-full ${isEnabled ? 'bg-blue-500' : 'bg-gray-400'}`}></div>
          <span className="font-medium">{isEnabled ? 'Enabled' : 'Disabled'}</span>
        </div>
      </div>

      <div className="flex gap-2">
        <button
          onClick={() => controls.studioMode.setStudioModeEnabled(!isEnabled)}
          className={`flex-1 rounded px-4 py-2 text-white hover:opacity-90 ${
            isEnabled ? 'bg-red-500' : 'bg-blue-500'
          }`}
        >
          {isEnabled ? '🚫 Disable' : '🎛️ Enable'}
        </button>
        {isEnabled && (
          <button
            onClick={controls.studioMode.triggerTransition}
            className="flex-1 rounded bg-green-500 px-4 py-2 text-white hover:bg-green-600"
          >
            🔄 Transition
          </button>
        )}
      </div>
    </div>
  )
}

function AdditionalControls() {
  const virtualCam = useOBSVirtualCam()
  const replayBuffer = useOBSReplayBuffer()
  const controls = useOBSControls()

  const isVirtualCamActive = virtualCam?.active || false
  const isReplayBufferActive = replayBuffer?.active || false

  return (
    <div className="rounded-lg border bg-white p-4">
      <h3 className="mb-4 text-lg font-semibold">Additional Controls</h3>
      
      <div className="space-y-4">
        {/* Virtual Camera */}
        <div>
          <div className="mb-2 flex items-center gap-2">
            <div className={`h-3 w-3 rounded-full ${isVirtualCamActive ? 'bg-green-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Virtual Camera</span>
          </div>
          <div className="flex gap-2">
            <button
              onClick={controls.virtualCam.startVirtualCam}
              disabled={isVirtualCamActive}
              className="flex-1 rounded bg-green-500 px-3 py-2 text-sm text-white hover:bg-green-600 disabled:bg-gray-400"
            >
              📹 Start
            </button>
            <button
              onClick={controls.virtualCam.stopVirtualCam}
              disabled={!isVirtualCamActive}
              className="flex-1 rounded bg-red-500 px-3 py-2 text-sm text-white hover:bg-red-600 disabled:bg-gray-400"
            >
              ⏹️ Stop
            </button>
          </div>
        </div>

        {/* Replay Buffer */}
        <div>
          <div className="mb-2 flex items-center gap-2">
            <div className={`h-3 w-3 rounded-full ${isReplayBufferActive ? 'bg-purple-500' : 'bg-gray-400'}`}></div>
            <span className="font-medium">Replay Buffer</span>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <button
              onClick={controls.replayBuffer.startReplayBuffer}
              disabled={isReplayBufferActive}
              className="rounded bg-purple-500 px-3 py-2 text-sm text-white hover:bg-purple-600 disabled:bg-gray-400"
            >
              ⏺️ Start
            </button>
            <button
              onClick={controls.replayBuffer.stopReplayBuffer}
              disabled={!isReplayBufferActive}
              className="rounded bg-red-500 px-3 py-2 text-sm text-white hover:bg-red-600 disabled:bg-gray-400"
            >
              ⏹️ Stop
            </button>
            <button
              onClick={controls.replayBuffer.saveReplayBuffer}
              disabled={!isReplayBufferActive}
              className="rounded bg-blue-500 px-3 py-2 text-sm text-white hover:bg-blue-600 disabled:bg-gray-400"
            >
              💾 Save
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

export function OBSDashboard() {
  return (
    <div className="space-y-6">
      <header className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">OBS Studio</h2>
          <p className="text-gray-600">Real-time control and monitoring</p>
        </div>
        <ConnectionStatus />
      </header>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <SceneControls />
        </div>
        
        <StreamingControls />
        <RecordingControls />
        <StudioModeControls />
        <AdditionalControls />
      </div>
    </div>
  )
}
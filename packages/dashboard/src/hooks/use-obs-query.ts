import { useEffect, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { UseMutationOptions } from '@tanstack/react-query'
import { trpcClient } from '@/lib/trpc-client'
import type { OBSState } from '@landale/shared'

// Query keys factory for OBS
export const obsKeys = {
  all: ['obs'] as const,
  scenes: () => [...obsKeys.all, 'scenes'] as const,
  streaming: () => [...obsKeys.all, 'streaming'] as const,
  recording: () => [...obsKeys.all, 'recording'] as const,
  studioMode: () => [...obsKeys.all, 'studioMode'] as const,
  virtualCam: () => [...obsKeys.all, 'virtualCam'] as const,
  replayBuffer: () => [...obsKeys.all, 'replayBuffer'] as const,
  connection: () => [...obsKeys.all, 'connection'] as const,
}

/**
 * Hook to sync WebSocket subscriptions with React Query cache
 */
function useOBSSubscription<T>(
  key: readonly string[],
  subscribeFn: (onData: (data: T) => void) => { unsubscribe: () => void }
) {
  const queryClient = useQueryClient()

  useEffect(() => {
    const subscription = subscribeFn((data) => {
      queryClient.setQueryData(key, data)
    })

    return () => subscription.unsubscribe()
  }, [queryClient, subscribeFn])
}

/**
 * Helper to create optimistic mutations with consistent error handling
 */
function createOptimisticMutation<T, TData = unknown, TVariables = void>(
  queryClient: ReturnType<typeof useQueryClient>,
  queryKey: readonly string[],
  mutationFn: (variables: TVariables) => Promise<TData>,
  optimisticUpdate: (previous: T, variables?: TVariables) => T
): UseMutationOptions<TData, Error, TVariables, { previous: T | undefined }> {
  return {
    mutationFn,
    onMutate: async (variables) => {
      await queryClient.cancelQueries({ queryKey })
      const previous = queryClient.getQueryData<T>(queryKey)
      
      if (previous) {
        queryClient.setQueryData<T>(queryKey, optimisticUpdate(previous, variables))
      }
      
      return { previous }
    },
    onError: (_err, _vars, context) => {
      if (context?.previous) {
        queryClient.setQueryData(queryKey, context.previous)
      }
    },
  }
}

/**
 * OBS Connection Status
 */
export function useOBSConnection() {
  const query = useQuery({
    queryKey: obsKeys.connection(),
    queryFn: () => null as OBSState['connection'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['connection']) => void) => 
      trpcClient.control.obs.onConnectionUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.connection(), subscribe)

  return {
    connection: query.data,
    isConnected: query.data?.connected ?? false,
  }
}

/**
 * OBS Scenes with optimistic updates
 */
export function useOBSScenes() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.scenes(),
    queryFn: () => null as OBSState['scenes'] | null,
    staleTime: Infinity,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['scenes']) => void) => 
      trpcClient.control.obs.scenes.onScenesUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.scenes(), subscribe)

  const setCurrentScene = useMutation<{ success: boolean }, Error, string, { previous: OBSState['scenes'] | undefined }>({
    mutationFn: (sceneName) => 
      trpcClient.control.obs.scenes.setCurrentScene.mutate({ sceneName }),
    onMutate: async (sceneName) => {
      await queryClient.cancelQueries({ queryKey: obsKeys.scenes() })
      const previous = queryClient.getQueryData<OBSState['scenes']>(obsKeys.scenes())
      
      if (previous) {
        queryClient.setQueryData<OBSState['scenes']>(obsKeys.scenes(), {
          ...previous,
          current: sceneName
        })
      }
      
      return { previous }
    },
    onError: (_err, _sceneName, context) => {
      if (context?.previous) {
        queryClient.setQueryData(obsKeys.scenes(), context.previous)
      }
    },
  })

  const setPreviewScene = useMutation<{ success: boolean }, Error, string, { previous: OBSState['scenes'] | undefined }>({
    mutationFn: (sceneName) => 
      trpcClient.control.obs.scenes.setPreviewScene.mutate({ sceneName }),
    onMutate: async (sceneName) => {
      await queryClient.cancelQueries({ queryKey: obsKeys.scenes() })
      const previous = queryClient.getQueryData<OBSState['scenes']>(obsKeys.scenes())
      
      if (previous) {
        queryClient.setQueryData<OBSState['scenes']>(obsKeys.scenes(), {
          ...previous,
          preview: sceneName
        })
      }
      
      return { previous }
    },
    onError: (_err, _sceneName, context) => {
      if (context?.previous) {
        queryClient.setQueryData(obsKeys.scenes(), context.previous)
      }
    },
  })

  return {
    scenes: query.data,
    currentScene: query.data?.current,
    previewScene: query.data?.preview,
    sceneList: query.data?.list || [],
    isLoading: query.data === null,
    setCurrentScene: setCurrentScene.mutate,
    setPreviewScene: setPreviewScene.mutate,
    isSettingScene: setCurrentScene.isPending || setPreviewScene.isPending,
  }
}

/**
 * OBS Streaming with optimistic updates
 */
export function useOBSStreaming() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.streaming(),
    queryFn: () => null as OBSState['streaming'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['streaming']) => void) => 
      trpcClient.control.obs.streaming.onStreamingUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.streaming(), subscribe)

  const startStream = useMutation(
    createOptimisticMutation<OBSState['streaming']>(
      queryClient,
      obsKeys.streaming(),
      () => trpcClient.control.obs.streaming.start.mutate(),
      (prev) => ({ ...prev, active: true })
    )
  )

  const stopStream = useMutation(
    createOptimisticMutation<OBSState['streaming']>(
      queryClient,
      obsKeys.streaming(),
      () => trpcClient.control.obs.streaming.stop.mutate(),
      (prev) => ({ ...prev, active: false })
    )
  )

  return {
    streaming: query.data,
    isStreaming: query.data?.active ?? false,
    startStream: startStream.mutate,
    stopStream: stopStream.mutate,
    isToggling: startStream.isPending || stopStream.isPending,
  }
}

/**
 * OBS Recording with optimistic updates
 */
export function useOBSRecording() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.recording(),
    queryFn: () => null as OBSState['recording'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['recording']) => void) => 
      trpcClient.control.obs.recording.onRecordingUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.recording(), subscribe)

  const startRecording = useMutation(
    createOptimisticMutation<OBSState['recording']>(
      queryClient,
      obsKeys.recording(),
      () => trpcClient.control.obs.recording.start.mutate(),
      (prev) => ({ ...prev, active: true, paused: false })
    )
  )

  const stopRecording = useMutation(
    createOptimisticMutation<OBSState['recording']>(
      queryClient,
      obsKeys.recording(),
      () => trpcClient.control.obs.recording.stop.mutate(),
      (prev) => ({ ...prev, active: false, paused: false })
    )
  )

  const pauseRecording = useMutation(
    createOptimisticMutation<OBSState['recording']>(
      queryClient,
      obsKeys.recording(),
      () => trpcClient.control.obs.recording.pause.mutate(),
      (prev) => ({ ...prev, paused: true })
    )
  )

  const resumeRecording = useMutation(
    createOptimisticMutation<OBSState['recording']>(
      queryClient,
      obsKeys.recording(),
      () => trpcClient.control.obs.recording.resume.mutate(),
      (prev) => ({ ...prev, paused: false })
    )
  )

  return {
    recording: query.data,
    isRecording: query.data?.active ?? false,
    isPaused: query.data?.paused ?? false,
    startRecording: startRecording.mutate,
    stopRecording: stopRecording.mutate,
    pauseRecording: pauseRecording.mutate,
    resumeRecording: resumeRecording.mutate,
    isToggling: startRecording.isPending || stopRecording.isPending,
  }
}

/**
 * OBS Studio Mode with optimistic updates
 */
export function useOBSStudioMode() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.studioMode(),
    queryFn: () => null as OBSState['studioMode'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['studioMode']) => void) => 
      trpcClient.control.obs.studioMode.onStudioModeUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.studioMode(), subscribe)

  const setEnabled = useMutation<{ success: boolean }, Error, boolean, { previous: OBSState['studioMode'] | undefined }>({
    mutationFn: (enabled) => 
      trpcClient.control.obs.studioMode.setEnabled.mutate({ enabled }),
    onMutate: async (enabled) => {
      await queryClient.cancelQueries({ queryKey: obsKeys.studioMode() })
      const previous = queryClient.getQueryData<OBSState['studioMode']>(obsKeys.studioMode())
      queryClient.setQueryData<OBSState['studioMode']>(obsKeys.studioMode(), { enabled })
      return { previous }
    },
    onError: (_err, _enabled, context) => {
      if (context?.previous) {
        queryClient.setQueryData(obsKeys.studioMode(), context.previous)
      }
    },
  })

  const triggerTransition = useMutation({
    mutationFn: () => trpcClient.control.obs.studioMode.triggerTransition.mutate(),
  })

  return {
    studioMode: query.data,
    isEnabled: query.data?.enabled ?? false,
    setEnabled: setEnabled.mutate,
    triggerTransition: triggerTransition.mutate,
    isToggling: setEnabled.isPending,
  }
}

/**
 * OBS Virtual Camera with optimistic updates
 */
export function useOBSVirtualCam() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.virtualCam(),
    queryFn: () => null as OBSState['virtualCam'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['virtualCam']) => void) => 
      trpcClient.control.obs.virtualCam.onVirtualCamUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.virtualCam(), subscribe)

  const start = useMutation(
    createOptimisticMutation<OBSState['virtualCam']>(
      queryClient,
      obsKeys.virtualCam(),
      () => trpcClient.control.obs.virtualCam.start.mutate(),
      () => ({ active: true })
    )
  )

  const stop = useMutation(
    createOptimisticMutation<OBSState['virtualCam']>(
      queryClient,
      obsKeys.virtualCam(),
      () => trpcClient.control.obs.virtualCam.stop.mutate(),
      () => ({ active: false })
    )
  )

  return {
    virtualCam: query.data,
    isActive: query.data?.active ?? false,
    start: start.mutate,
    stop: stop.mutate,
    isToggling: start.isPending || stop.isPending,
  }
}

/**
 * OBS Replay Buffer with optimistic updates
 */
export function useOBSReplayBuffer() {
  const queryClient = useQueryClient()
  
  const query = useQuery({
    queryKey: obsKeys.replayBuffer(),
    queryFn: () => null as OBSState['replayBuffer'] | null,
  })

  const subscribe = useCallback(
    (onData: (data: OBSState['replayBuffer']) => void) => 
      trpcClient.control.obs.replayBuffer.onReplayBufferUpdate.subscribe(undefined, { onData }),
    []
  )

  useOBSSubscription(obsKeys.replayBuffer(), subscribe)

  const start = useMutation(
    createOptimisticMutation<OBSState['replayBuffer']>(
      queryClient,
      obsKeys.replayBuffer(),
      () => trpcClient.control.obs.replayBuffer.start.mutate(),
      () => ({ active: true })
    )
  )

  const stop = useMutation(
    createOptimisticMutation<OBSState['replayBuffer']>(
      queryClient,
      obsKeys.replayBuffer(),
      () => trpcClient.control.obs.replayBuffer.stop.mutate(),
      () => ({ active: false })
    )
  )

  const save = useMutation({
    mutationFn: () => trpcClient.control.obs.replayBuffer.save.mutate(),
  })

  return {
    replayBuffer: query.data,
    isActive: query.data?.active ?? false,
    start: start.mutate,
    stop: stop.mutate,
    save: save.mutate,
    isToggling: start.isPending || stop.isPending,
  }
}

/**
 * Aggregated OBS controls for convenience
 */
export function useOBSControls() {
  const streaming = useOBSStreaming()
  const recording = useOBSRecording()
  const studioMode = useOBSStudioMode()
  const virtualCam = useOBSVirtualCam()
  const replayBuffer = useOBSReplayBuffer()

  return {
    streaming: {
      startStream: streaming.startStream,
      stopStream: streaming.stopStream,
    },
    recording: {
      startRecording: recording.startRecording,
      stopRecording: recording.stopRecording,
      pauseRecording: recording.pauseRecording,
      resumeRecording: recording.resumeRecording,
    },
    studioMode: {
      setStudioModeEnabled: studioMode.setEnabled,
      triggerTransition: studioMode.triggerTransition,
    },
    virtualCam: {
      startVirtualCam: virtualCam.start,
      stopVirtualCam: virtualCam.stop,
    },
    replayBuffer: {
      startReplayBuffer: replayBuffer.start,
      stopReplayBuffer: replayBuffer.stop,
      saveReplayBuffer: replayBuffer.save,
    },
  }
}
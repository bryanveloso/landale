import { Activity, Play, Square, RotateCw, AlertCircle, CheckCircle, Loader2 } from 'lucide-react'
import { useSubscription } from '@/hooks/use-subscription'
import { trpcClient } from '@/lib/trpc-client'
import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'

interface ProcessInfo {
  name: string
  pm_id: number
  status: 'online' | 'stopping' | 'stopped' | 'launching' | 'errored'
  cpu: number
  memory: number
  uptime: number
  restart_time: number
  unstable_restarts: number
}

interface PM2StatusProps {
  machine?: string
}

interface ConfirmDialog {
  isOpen: boolean
  action: 'start' | 'stop' | 'restart' | null
  processName: string | null
  machine: string | null
}

// Known machines in the network
const MACHINES = [
  { id: 'localhost', name: 'Local', icon: '🏠' },
  { id: 'saya', name: 'Saya (Mac Mini)', icon: '🖥️' },
  { id: 'zelan', name: 'Zelan (Mac Studio)', icon: '💻' },
  { id: 'demi', name: 'Demi (Windows OBS)', icon: '🎬' },
  { id: 'alys', name: 'Alys (Windows Gaming)', icon: '🎮' }
]

export function PM2Status({ machine }: PM2StatusProps) {
  const [selectedMachine, setSelectedMachine] = useState(machine || 'localhost')
  const [actionInProgress, setActionInProgress] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [confirmDialog, setConfirmDialog] = useState<ConfirmDialog>({
    isOpen: false,
    action: null,
    processName: null,
    machine: null
  })

  const {
    data: processes,
    connectionState,
    isConnected,
    isError
  } = useSubscription<ProcessInfo[]>('processes.onStatusUpdate', { machine: selectedMachine }, {
    onData: (data) => {
      console.log(`[Dashboard] Received ${data.length} processes for ${selectedMachine}:`, data)
    },
    onError: (error) => {
      console.error(`[Dashboard] Subscription error for ${selectedMachine}:`, error)
    },
    onConnectionStateChange: (state) => {
      console.log(`[Dashboard] Connection state changed for ${selectedMachine}:`, state)
    }
  })

  const startMutation = useMutation({
    mutationFn: ({ machine, process }: { machine: string; process: string }) => 
      trpcClient.processes.start.mutate({ machine, process })
  })

  const stopMutation = useMutation({
    mutationFn: ({ machine, process }: { machine: string; process: string }) => 
      trpcClient.processes.stop.mutate({ machine, process })
  })

  const restartMutation = useMutation({
    mutationFn: ({ machine, process }: { machine: string; process: string }) => 
      trpcClient.processes.restart.mutate({ machine, process })
  })

  const openConfirmDialog = (action: 'start' | 'stop' | 'restart', processName: string) => {
    setConfirmDialog({ isOpen: true, action, processName, machine: selectedMachine })
  }

  const closeConfirmDialog = () => {
    setConfirmDialog({ isOpen: false, action: null, processName: null, machine: null })
  }

  const handleAction = async () => {
    if (!confirmDialog.action || !confirmDialog.processName || !confirmDialog.machine) return
    
    setError(null)
    setActionInProgress(`${confirmDialog.action}-${confirmDialog.processName}`)
    closeConfirmDialog()
    
    try {
      const mutations = {
        start: startMutation,
        stop: stopMutation,
        restart: restartMutation
      }
      
      const mutation = mutations[confirmDialog.action]
      await mutation.mutateAsync({ 
        machine: confirmDialog.machine, 
        process: confirmDialog.processName 
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed')
    } finally {
      setActionInProgress(null)
    }
  }

  const getStatusIcon = (status: ProcessInfo['status']) => {
    switch (status) {
      case 'online':
        return <CheckCircle className="h-4 w-4 text-green-500" />
      case 'stopped':
        return <Square className="h-4 w-4 text-gray-500" />
      case 'launching':
        return <Loader2 className="h-4 w-4 animate-spin text-yellow-500" />
      case 'errored':
        return <AlertCircle className="h-4 w-4 text-red-500" />
      default:
        return <Activity className="h-4 w-4 text-gray-500" />
    }
  }

  const getStatusColor = (status: ProcessInfo['status']) => {
    switch (status) {
      case 'online':
        return 'text-green-400'
      case 'stopped':
        return 'text-gray-400'
      case 'launching':
        return 'text-yellow-400'
      case 'errored':
        return 'text-red-400'
      default:
        return 'text-gray-400'
    }
  }

  const formatMemory = (bytes: number) => {
    const mb = bytes / 1024 / 1024
    return `${mb.toFixed(1)} MB`
  }

  const formatUptime = (ms: number) => {
    const seconds = Math.floor(ms / 1000)
    const minutes = Math.floor(seconds / 60)
    const hours = Math.floor(minutes / 60)
    const days = Math.floor(hours / 24)

    if (days > 0) return `${days}d ${hours % 24}h`
    if (hours > 0) return `${hours}h ${minutes % 60}m`
    if (minutes > 0) return `${minutes}m ${seconds % 60}s`
    return `${seconds}s`
  }

  const getConnectionIcon = () => {
    const state = connectionState.state
    if (state === 'connected') return <Activity className="h-4 w-4 text-green-500" />
    if (state === 'error') return <AlertCircle className="h-4 w-4 text-red-500" />
    return <Loader2 className="h-4 w-4 animate-spin text-gray-500" />
  }

  return (
    <div className="rounded-lg bg-gray-800 p-6">
      <div className="mb-4">
        <div className="flex items-center justify-between mb-4">
          <h2 className="flex items-center gap-2 text-xl font-semibold">
            {isError ? (
              <AlertCircle className="h-5 w-5 text-red-500" />
            ) : (
              <Activity className="h-5 w-5 text-green-500" />
            )}
            PM2 Processes
          </h2>
          {getConnectionIcon()}
        </div>
        
        {/* Machine selector tabs */}
        <div className="flex gap-1 bg-gray-900/50 rounded-lg p-1">
          {MACHINES.map(machine => (
            <button
              key={machine.id}
              onClick={() => setSelectedMachine(machine.id)}
              className={`flex items-center gap-2 px-3 py-2 rounded transition-colors ${
                selectedMachine === machine.id
                  ? 'bg-gray-700 text-white'
                  : 'text-gray-400 hover:text-white hover:bg-gray-800'
              }`}
            >
              <span>{machine.icon}</span>
              <span className="text-sm font-medium">{machine.name}</span>
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded bg-red-900/50 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      {isError && (
        <div className="text-sm text-red-400">
          {connectionState.error || `Unable to connect to PM2 on ${selectedMachine}`}
        </div>
      )}

      {isConnected && (!processes || processes.length === 0) && (
        <div className="text-center text-gray-400 py-8">
          No processes managed by PM2 on {selectedMachine}
        </div>
      )}

      {isConnected && processes && processes.length > 0 && (
        <div className="space-y-3">
          {processes.map((process) => (
            <div
              key={process.pm_id}
              className="rounded-lg bg-gray-900/50 p-4 transition-colors hover:bg-gray-900/70"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    {getStatusIcon(process.status)}
                    <h3 className="font-medium text-gray-100">{process.name}</h3>
                    <span className={`text-xs uppercase ${getStatusColor(process.status)}`}>
                      {process.status}
                    </span>
                    {selectedMachine !== 'localhost' && (
                      <span className="text-xs px-2 py-0.5 bg-gray-700 text-gray-300 rounded">
                        {MACHINES.find(m => m.id === selectedMachine)?.icon}
                      </span>
                    )}
                  </div>

                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div className="space-y-1">
                      <div className="flex justify-between">
                        <span className="text-gray-400">CPU</span>
                        <span>{process.cpu.toFixed(1)}%</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-400">Memory</span>
                        <span>{formatMemory(process.memory)}</span>
                      </div>
                    </div>
                    <div className="space-y-1">
                      <div className="flex justify-between">
                        <span className="text-gray-400">Uptime</span>
                        <span>{formatUptime(Date.now() - process.uptime)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-400">Restarts</span>
                        <span className={process.unstable_restarts > 0 ? 'text-yellow-400' : ''}>
                          {process.restart_time}
                        </span>
                      </div>
                    </div>
                  </div>

                  {process.unstable_restarts > 0 && (
                    <div className="mt-2 text-xs text-yellow-400">
                      {process.unstable_restarts} unstable restarts
                    </div>
                  )}
                </div>

                <div className="flex gap-1 ml-4">
                  {process.status === 'stopped' && (
                    <button
                      onClick={() => openConfirmDialog('start', process.name)}
                      disabled={actionInProgress !== null}
                      className="rounded p-1.5 text-gray-400 hover:bg-gray-700 hover:text-green-400 disabled:opacity-50"
                      title="Start"
                    >
                      {actionInProgress === `start-${process.name}` ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <Play className="h-4 w-4" />
                      )}
                    </button>
                  )}
                  
                  {process.status === 'online' && (
                    <>
                      <button
                        onClick={() => openConfirmDialog('stop', process.name)}
                        disabled={actionInProgress !== null}
                        className="rounded p-1.5 text-gray-400 hover:bg-gray-700 hover:text-red-400 disabled:opacity-50"
                        title="Stop"
                      >
                        {actionInProgress === `stop-${process.name}` ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <Square className="h-4 w-4" />
                        )}
                      </button>
                      <button
                        onClick={() => openConfirmDialog('restart', process.name)}
                        disabled={actionInProgress !== null}
                        className="rounded p-1.5 text-gray-400 hover:bg-gray-700 hover:text-yellow-400 disabled:opacity-50"
                        title="Restart"
                      >
                        {actionInProgress === `restart-${process.name}` ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <RotateCw className="h-4 w-4" />
                        )}
                      </button>
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Confirmation Dialog */}
      {confirmDialog.isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="rounded-lg bg-gray-800 p-6 shadow-xl max-w-sm w-full mx-4">
            <h3 className="text-lg font-semibold mb-4">
              Confirm {confirmDialog.action}
            </h3>
            <p className="text-gray-300 mb-6">
              Are you sure you want to {confirmDialog.action} the process{' '}
              <span className="font-mono text-yellow-400">{confirmDialog.processName}</span>
              {confirmDialog.machine !== 'localhost' && (
                <span className="text-gray-400"> on {MACHINES.find(m => m.id === confirmDialog.machine)?.name}</span>
              )}?
            </p>
            <div className="flex gap-3 justify-end">
              <button
                onClick={closeConfirmDialog}
                className="px-4 py-2 rounded bg-gray-700 hover:bg-gray-600 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleAction}
                className={`px-4 py-2 rounded transition-colors ${
                  confirmDialog.action === 'stop' 
                    ? 'bg-red-600 hover:bg-red-700' 
                    : confirmDialog.action === 'start' 
                    ? 'bg-green-600 hover:bg-green-700'
                    : 'bg-yellow-600 hover:bg-yellow-700'
                }`}
              >
                {confirmDialog.action === 'stop' ? 'Stop' : 
                 confirmDialog.action === 'start' ? 'Start' : 'Restart'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
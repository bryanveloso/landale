import { createFileRoute } from '@tanstack/solid-router'
import { createSignal, createResource, Show, onMount } from 'solid-js'

interface OAuthStatus {
  connected: boolean
  expires_at?: string
  valid?: boolean
}

const API_BASE = 'http://saya:7175/api/oauth'

export const Route = createFileRoute('/oauth')({
  component: OAuthPage
})

function OAuthPage() {
  const [isRefreshing, setIsRefreshing] = createSignal(false)
  const [error, setError] = createSignal<string | null>(null)
  const [successMessage, setSuccessMessage] = createSignal<string | null>(null)

  // Fetch current OAuth status
  const [status, { refetch }] = createResource<OAuthStatus>(async () => {
    try {
      const response = await fetch(`${API_BASE}/status`)
      if (!response.ok) {
        throw new Error(`Failed to fetch status: ${response.statusText}`)
      }
      return await response.json()
    } catch (err) {
      console.error('Failed to fetch OAuth status:', err)
      return { connected: false }
    }
  })

  // Handle token refresh
  const handleRefresh = async () => {
    setIsRefreshing(true)
    setError(null)
    try {
      const response = await fetch(`${API_BASE}/refresh`, { method: 'POST' })
      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || `Failed to refresh token`)
      }
      setSuccessMessage('Token refreshed successfully!')
      setTimeout(() => setSuccessMessage(null), 5000)
      await refetch()
    } catch (err: any) {
      setError(err.message)
      setTimeout(() => setError(null), 5000)
    } finally {
      setIsRefreshing(false)
    }
  }

  // Check for callback params
  onMount(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.get('success') === 'true') {
      setSuccessMessage('OAuth connection successful!')
      setTimeout(() => setSuccessMessage(null), 5000)
      refetch()
    } else if (params.has('error')) {
      setError(`OAuth failed: ${params.get('error')}`)
      setTimeout(() => setError(null), 5000)
    }
  })

  return (
    <div class="container mx-auto max-w-4xl px-4 py-8">
      <h1 class="mb-8 text-3xl font-bold text-white">OAuth Management</h1>

      {/* Messages */}
      <Show when={error()}>
        <div class="mb-4 rounded border border-red-500 bg-red-900/50 px-4 py-3 text-red-200">
          <p class="font-bold">Error</p>
          <p>{error()}</p>
        </div>
      </Show>

      <Show when={successMessage()}>
        <div class="mb-4 rounded border border-green-500 bg-green-900/50 px-4 py-3 text-green-200">
          <p>{successMessage()}</p>
        </div>
      </Show>

      {/* OAuth Status */}
      <div class="rounded-lg bg-gray-800 p-6 shadow-lg">
        <h2 class="mb-4 text-xl font-semibold text-white">Twitch Connection</h2>

        <Show when={status.loading}>
          <p class="text-gray-400">Loading OAuth status...</p>
        </Show>

        <Show when={!status.loading && status()}>
          {(currentStatus) => (
            <Show
              when={currentStatus().connected}
              fallback={
                <div class="space-y-4">
                  <div class="flex items-center space-x-2">
                    <div class="h-3 w-3 rounded-full bg-red-500"></div>
                    <span class="text-gray-300">Not Connected</span>
                  </div>

                  <a
                    href="http://saya:7175/api/oauth/authorize"
                    class="inline-block rounded bg-purple-600 px-4 py-2 font-bold text-white transition-colors hover:bg-purple-700">
                    Connect Twitch Account
                  </a>
                </div>
              }>
              <div class="space-y-4">
                <div class="flex items-center space-x-2">
                  <div class="h-3 w-3 animate-pulse rounded-full bg-green-500"></div>
                  <span class="text-gray-300">Connected</span>
                </div>

                <Show when={currentStatus().expires_at}>
                  <div class="flex items-center space-x-2">
                    <span class="text-gray-400">Token expires:</span>
                    <span class={currentStatus().valid ? 'text-gray-300' : 'text-red-400'}>
                      {new Date(currentStatus().expires_at!).toLocaleString()}
                    </span>
                  </div>
                </Show>

                <button
                  onClick={handleRefresh}
                  disabled={isRefreshing()}
                  class="rounded bg-blue-600 px-4 py-2 font-bold text-white transition-colors hover:bg-blue-700 disabled:bg-blue-800">
                  {isRefreshing() ? 'Refreshing...' : 'Refresh Token'}
                </button>
              </div>
            </Show>
          )}
        </Show>
      </div>

      {/* Info */}
      <div class="mt-8 rounded-lg bg-gray-800 p-6">
        <h3 class="mb-3 text-lg font-semibold text-white">About OAuth</h3>
        <div class="space-y-2 text-sm text-gray-400">
          <p>• This connection allows Landale to interact with your Twitch account</p>
          <p>• Tokens are automatically refreshed when needed</p>
          <p>• Running on Tailscale network - no external authentication needed</p>
        </div>
      </div>
    </div>
  )
}

import { createFileRoute } from '@tanstack/solid-router'
import { Omnibar } from '@/components/omnibar'
import { DebugProvider } from '@/providers/debug-provider'
import { useOmnibar } from '@/hooks/use-omnibar'
import { useStreamChannel } from '@/hooks/use-stream-channel'

export const Route = createFileRoute('/omnibar')({
  component: RouteComponent
})

function RouteComponent() {
  return <OmnibarWithDebug />
}

// Wrapper component to provide debug context
function OmnibarWithDebug() {
  // Get references for debug interface
  const omnibar = useOmnibar()
  const streamChannel = useStreamChannel()

  return (
    <DebugProvider orchestrator={omnibar} streamChannel={streamChannel}>
      <div class="w-canvas h-canvas flex items-end">
        <Omnibar />
      </div>
    </DebugProvider>
  )
}

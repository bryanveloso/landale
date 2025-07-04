import { createFileRoute } from '@tanstack/react-router'
import { NowPlaying } from '@/components/now-playing'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/now-playing')({
  component: NowPlayingRoute
})

function NowPlayingRoute() {
  return (
    <ErrorBoundary>
      <NowPlaying />
    </ErrorBoundary>
  )
}

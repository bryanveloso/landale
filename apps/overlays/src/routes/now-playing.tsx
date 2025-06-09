import { createFileRoute } from '@tanstack/react-router'
import { NowPlaying } from '@/components/now-playing'

export const Route = createFileRoute('/now-playing')({
  component: NowPlayingRoute
})

function NowPlayingRoute() {
  return <NowPlaying />
}

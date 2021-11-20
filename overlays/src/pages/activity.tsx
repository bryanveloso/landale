import { AspectRatio } from '@radix-ui/react-aspect-ratio'
import { Screen } from '../components/screen'
import { Window } from '../components/window'
import { styled } from '../stitches.config'

export default function Activity() {
  return (
    <Screen>
      <Window size="content-972p" css={{ margin: 54 }} />
      <Window
        size="secondary-434p"
        css={{ right: 54, top: 323, background: '#1F2027' }}
      />
    </Screen>
  )
}

const Widescreen = styled(AspectRatio, {
  background: 'AliceBlue'
})

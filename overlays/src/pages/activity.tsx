import { AspectRatio } from '@radix-ui/react-aspect-ratio'
import { Box } from '../components/box'
import { Screen } from '../components/screen'
import { styled } from '../stitches.config'

export default function Activity() {
  return (
    <Screen>
      <Box css={{ width: '640px', gridColumn: 2, gridRow: 4 }}>
        <Widescreen ratio={21 / 9}></Widescreen>
      </Box>
    </Screen>
  )
}

const Widescreen = styled(AspectRatio, {
  background: 'AliceBlue'
})

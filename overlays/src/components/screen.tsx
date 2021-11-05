import { styled } from '../stitches.config'

export const Screen = styled('div', {
  // Box Model.
  display: 'grid',
  gridTemplateColumns: 'repeat(3, 1fr)',
  gridTemplateRows: 'repeat(4, 1fr)',

  // Dimensions.
  width: 1920,
  height: 1080
})

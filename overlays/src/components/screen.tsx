import { styled } from '../stitches.config'

export const Screen = styled('div', {
  // Box Model.
  display: 'grid',
  gridTemplateColumns: 'repeat(3, 1fr)',
  gridTemplateRows: 'repeat(20, 54px)',

  // Dimensions.
  width: 1920,
  height: 1080,

  variants: {
    padded: {
      true: {
        padding: '54px'
      }
    }
  }
})

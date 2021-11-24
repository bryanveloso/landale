import { styled } from '../stitches.config'

export const Screen = styled('div', {
  // Box Model.
  position: 'relative',

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

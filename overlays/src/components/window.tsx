import { styled } from '../stitches.config'

export const Window = styled('div', {
  // Box Model.
  position: 'absolute',

  // Chrome.
  borderRadius: 9,
  background: 'transparent',

  variants: {
    size: {
      'content-972p': {
        height: 972,
        width: 1728
      },
      'secondary-434p': {
        height: 434,
        width: 360
      }
    },
    shadow: {
      osx: {
        boxShadow:
          'inset 0 0 0 2px rgba(255, 255, 255, .34), 0 0 0 2px rgba(0, 0, 0, 0.8), 0 22px 70px 4px rgba(0, 0, 0, 0.56)'
      }
    }
  },

  defaultVariants: {
    size: 'content-972p',
    shadow: 'osx'
  }
})

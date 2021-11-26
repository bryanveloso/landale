import { styled } from '../stitches.config'

export const Window = styled('div', {
  // Box Model.
  position: 'absolute',

  // Chrome.
  '&::after': {
    content: '',
    position: 'absolute',
    top: 0,
    width: '100%',
    height: '100%',

    background: 'transparent',
    borderRadius: 9,
    boxShadow:
      'inset 0 0 0 2px rgba(255, 255, 255, .23), 0 0 0 2px rgba(0, 0, 0, 0.89), 0 24px 64px 4px rgba(0, 0, 0, 0.67)',
    zIndex: 1000
  },

  variants: {
    size: {
      '972p-full': {
        height: 972,
        width: 1728
      },
      '972p-half': {
        height: 972,
        width: 880
      },
      'secondary-434p': {
        height: 434,
        width: 360
      }
    }
  },

  defaultVariants: {
    size: 'content-972p'
  }
})

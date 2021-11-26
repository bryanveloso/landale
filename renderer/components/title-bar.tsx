import * as React from 'react'

import { styled, CSS, VariantProps } from '../stitches.config'

const Circle = styled('div', {
  height: 12,
  width: 12,
  borderRadius: '50%',
  background: 'gray'
})

const Title = styled('div', {
  flex: '1 0 auto',
  paddingLeft: 8,
  fontFamily: 'system-ui',
  color: '#868686'
})

const Bar = styled('div', {
  // Box Model.
  display: 'flex',
  gap: '8px',
  width: '100%',
  minHeight: '52px',
  padding: '0 20px',
  alignItems: 'center',
  zIndex: '-1',

  borderTopLeftRadius: 9,
  borderTopRightRadius: 9,

  variants: {
    style: {
      standard: {
        background: '#1F2027',
        boxShadow:
          'inset 0 -1px 0 rgba(0, 0, 0, 0.56), 0 1px 1px rgba(0, 0, 0, 0.34)'
      },
      translucent: {
        background: 'rgba(0, 0, 0, 0.25)'
      },
      transparent: {
        background: 'transparent'
      }
    },
    controls: {
      active: {
        [`& ${Circle}`]: { backgroundColor: '$controlClose' },
        [`& ${Circle} + ${Circle}`]: { backgroundColor: '$controlMinimize' },
        [`& ${Circle} + ${Circle} + ${Circle}`]: {
          backgroundColor: '$controlMaximize'
        }
      },
      inactive: {
        [`& ${Circle}`]: { backgroundColor: 'gray' }
      }
    }
  },

  defaultVariants: {
    style: 'standard'
  }
})

type TitleBarProps = React.ComponentProps<typeof Bar> &
  VariantProps<typeof Bar> & { css?: CSS }

export const TitleBar = React.forwardRef<
  React.ElementRef<typeof Bar>,
  TitleBarProps
>(({ children, ...props }, forwardedRef) => (
  <Bar {...props} ref={forwardedRef}>
    <Circle />
    <Circle />
    <Circle />
    <Title>{children}</Title>
  </Bar>
))

TitleBar.displayName = 'TitleBar'

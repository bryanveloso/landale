import {
  gray,
  blue,
  red,
  green,
  grayDark,
  blueDark,
  redDark,
  greenDark
} from '@radix-ui/colors'
import { createStitches } from '@stitches/react'

export const {
  styled,
  css,
  globalCss,
  keyframes,
  getCssText,
  theme,
  createTheme,
  config
} = createStitches({})

export const normalize: Record<string, any>[] = []

export const globalStyles = globalCss({
  body: {
    fontFamily: 'InterVariant, sans-serif',
    margin: 0
  }
})

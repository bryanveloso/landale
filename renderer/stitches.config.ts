import {
  slate,
  blue,
  red,
  green,
  slateDark,
  blueDark,
  redDark,
  greenDark
} from '@radix-ui/colors'

import { createStitches } from '@stitches/react'

import type * as Stitches from '@stitches/react'
export type { VariantProps } from '@stitches/react'

export const {
  styled,
  css,
  globalCss,
  keyframes,
  getCssText,
  theme,
  createTheme,
  config
} = createStitches({
  theme: {
    colors: {
      // App Colors
      ...slate,
      ...blue,
      ...red,
      ...green,

      // Semantic Colors
      controlClose: '#DA7169',
      controlMinimize: '#EABE6A',
      controlMaximize: '#7DBF67'
    }
  }
})

export const darkTheme = createTheme('dark', {
  colors: {
    ...slateDark,
    ...blueDark,
    ...redDark,
    ...greenDark
  }
})

export const modes = [darkTheme, 'light']

export type CSS = Stitches.CSS<typeof config>

export const normalize: Record<string, CSS>[] = [
  {
    ':where(*, *::before, *::after)': { boxSizing: 'border-box' },
    ':where(*)': { margin: 0 },
    ':where(html, body)': { height: '100%' },
    ':where(body)': { lineHeight: 1.5 },
    ':where(img, picture, video, canvas, svg)': {
      display: 'block',
      maxWidth: '100%'
    },
    ':where(input, button, textarea, select)': { font: 'inherit' },
    ':where(p, h1, h2, h3, h4, h5, h6)': { overflowWrap: 'break-word' },
    ':where(#root, #__next)': { isolation: 'isolate' }
  }
]

export const globalStyles = globalCss(...normalize, {
  body: {
    fontFamily: 'system-ui',
    margin: 0
  },
  '#__next': {
    height: '100%'
  }
})

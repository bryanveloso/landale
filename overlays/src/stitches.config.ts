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
      controlClose: '#DA7169',
      controlMinimize: '#EABE6A',
      controlMaximize: '#7DBF67'
    }
  }
})

export const normalize: Record<string, any>[] = []

export type CSS = Stitches.CSS<typeof config>

export const globalStyles = globalCss({
  body: {
    fontFamily: 'system-ui',
    margin: 0
  }
})

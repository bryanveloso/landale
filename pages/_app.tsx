import '@fontsource/inter/variable-full.css'

import { NextPageWithLayout } from 'next'
import { ThemeProvider } from 'next-themes'

import { globalStyles, modes } from '../stitches.config'

import '../styles/loader.css'

function MyApp({ Component, pageProps }) {
  const getLayout =
    Component.getLayout ??
    ((page: NextPageWithLayout) => {
      page
    })

  // Set our global styles.
  globalStyles()

  return (
    <ThemeProvider enableSystem themes={modes} attribute="class">
      <Component {...pageProps} />
    </ThemeProvider>
  )
}

export default MyApp

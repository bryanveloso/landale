import '@fontsource/inter/variable-full.css'

import { NextPageWithLayout } from 'next'
import { ThemeProvider } from 'next-themes'

import { OBSProvider } from '../lib/providers/obs'
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
    <OBSProvider>
      <ThemeProvider enableSystem themes={modes} attribute="class">
        {getLayout(<Component {...pageProps} />)}
      </ThemeProvider>
    </OBSProvider>
  )
}

export default MyApp

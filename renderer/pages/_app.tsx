import '@fontsource/inter/variable-full.css'

import { globalStyles } from '../stitches.config'

import '../styles/loader.css'

function MyApp({ Component, pageProps }) {
  const getLayout =
    Component.getLayout ??
    ((page: NextPageWithLayout) => {
      page
    })

  // Set our global styles.
  globalStyles()

  return <Component {...pageProps} />
}

export default MyApp

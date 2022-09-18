import '@fontsource/inter/variable-full.css'

import '../styles/globals.css'

import type { AppProps } from 'next'

function MyApp({ Component, pageProps }: AppProps) {
  return <Component {...pageProps} />
}

export default MyApp

import '@fontsource/inter/variable-full.css'
import Layout from '../components/layout'

import { globalStyles } from '../stitches.config'

import '../styles/loader.css'

function MyApp({ Component, pageProps }) {
  globalStyles()
  return (
    <Layout>
      <Component {...pageProps} />
    </Layout>
  )
}

export default MyApp

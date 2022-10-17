import '@fontsource/inter/variable-full.css'

import '../styles/globals.css'

import type { AppProps } from 'next'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SpeechProvider } from '@speechly/react-client'

const queryClient = new QueryClient()

function MyApp({ Component, pageProps }: AppProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <SpeechProvider
        debug
        appId="b34ee859-cb63-40ad-8959-50b887f79f20"
        vad={{ enabled: true, signalSustainMillis: 2000 }}
      >
        <Component {...pageProps} />
      </SpeechProvider>
    </QueryClientProvider>
  )
}

export default MyApp

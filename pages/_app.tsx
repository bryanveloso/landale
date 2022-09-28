import '@fontsource/inter/variable-full.css'

import '../styles/globals.css'

import type { AppProps } from 'next'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const queryClient = new QueryClient()

import { ChannelProvider } from '~/lib/providers/channel'

function MyApp({ Component, pageProps }: AppProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <Component {...pageProps} />
    </QueryClientProvider>
  )
}

export default MyApp

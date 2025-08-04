import tailwindcss from '@tailwindcss/vite'
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import { defineConfig } from 'vite'
import solid from 'vite-plugin-solid'
import tsconfigPaths from 'vite-tsconfig-paths'

export default defineConfig({
  plugins: [tsconfigPaths(), tanstackRouter({ target: 'solid', autoCodeSplitting: true }), solid(), tailwindcss()],
  server: {
    allowedHosts: ['saya', 'zelan']
  }
})

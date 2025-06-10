import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  test: {
    globals: true,
    environment: 'happy-dom',
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '+': path.resolve(__dirname, './assets'),
      '~': path.resolve(__dirname, './public'),
    },
  },
})
import tailwindcss from '@tailwindcss/vite'
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import { defineConfig } from 'vite'
import solid from 'vite-plugin-solid'
import tsconfigPaths from 'vite-tsconfig-paths'

const host = process.env.TAURI_DEV_HOST || 'localhost'

export default defineConfig(async () => ({
  plugins: [
    tsconfigPaths(), 
    tanstackRouter({ target: 'solid', autoCodeSplitting: true }), 
    solid(), 
    tailwindcss()
  ],
  clearScreen: false,
  server: {
    host: host || false,
    port: 5174,
    strictPort: true,
    hmr: host ? {
      protocol: 'ws',
      host: host,
      port: 5175
    } : undefined,
    allowedHosts: ['zelan', 'localhost']
  },
  envPrefix: ['VITE_', 'TAURI_'],
  build: {
    target: process.env.TAURI_PLATFORM == 'windows' ? 'chrome105' : 'safari13',
    minify: !process.env.TAURI_DEBUG ? 'esbuild' : false,
    sourcemap: !!process.env.TAURI_DEBUG
  }
}))

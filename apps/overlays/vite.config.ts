import { TanStackRouterVite } from '@tanstack/router-vite-plugin'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'
import tailwindcss from '@tailwindcss/vite'
import tsconfigPaths from 'vite-tsconfig-paths'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), TanStackRouterVite(), tsconfigPaths(), tailwindcss()],
  server: {
    allowedHosts: ['.local'],
    host: true,
    port: 8008
  }
})

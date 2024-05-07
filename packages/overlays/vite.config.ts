import { TanStackRouterVite } from '@tanstack/router-vite-plugin';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), TanStackRouterVite()],
  server: {
    host: true,
    port: 8088,
  },
});

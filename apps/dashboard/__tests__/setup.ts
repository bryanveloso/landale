// Mock window object for tests
Object.defineProperty(globalThis, 'window', {
  value: {
    location: {
      protocol: 'http:',
      hostname: 'localhost',
      port: '3000'
    },
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout
  },
  writable: true
})

// Mock import.meta.env
Object.defineProperty(import.meta, 'env', {
  value: {
    VITE_SERVER_HOST: 'localhost',
    VITE_SERVER_PORT: '7175'
  },
  writable: true
})

import { PrismaClient } from '@prisma/client'

// Singleton pattern for Prisma Client
const prismaClientSingleton = () => {
  const client = new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error']
  })

  // In production, we'll use Accelerate through connection string
  // In development, we can add Optimize when API key is available
  return client
}

// Type declaration for global prisma instance
declare global {
  var prisma: ReturnType<typeof prismaClientSingleton> | undefined
}

// Create or reuse the global instance
const prisma = globalThis.prisma ?? prismaClientSingleton()

// Only cache the instance in development
if (process.env.NODE_ENV !== 'production') {
  globalThis.prisma = prisma
}

export default prisma
export { prisma }
export { Prisma } from '@prisma/client'

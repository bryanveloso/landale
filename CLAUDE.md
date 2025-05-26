# Landale Project Guidelines

## Project Overview
Landale is a monorepo streaming overlay system built with Bun, featuring real-time Twitch integration, game data processing, and animated overlays.

## Tech Stack
- **Runtime**: Bun (latest)
- **Frontend**: React 19, TanStack Router/Query, Vite, Tailwind CSS v4, Framer Motion, Matter.js, Rive
- **Backend**: tRPC, WebSocket, TCP sockets, Twitch EventSub/API
- **Database**: PostgreSQL with Prisma ORM
- **Development**: TypeScript (strict mode), ESLint, Prettier, Docker Compose

## Commands
### Root
- `bun dev` - Start all workspaces in development mode
- `bun run cache-emotes` - Cache Twitch emotes
- `docker compose up` - Run services in Docker

### Database Package
- `bun --cwd packages/database db:migrate:dev` - Run Prisma migrations
- `bun --cwd packages/database db:push` - Push schema changes without migration
- `bun --cwd packages/database studio` - Launch Prisma Studio
- `bun --cwd packages/database generate` - Generate Prisma client

### Overlays Package
- `bun --cwd packages/overlays dev` - Start Vite development server
- `bun --cwd packages/overlays build` - Build for production
- `bun --cwd packages/overlays preview` - Preview production build
- `bun --cwd packages/overlays lint` - Run ESLint
- `bun --cwd packages/overlays typecheck` - Run TypeScript type checking

### Server Package
- `bun --cwd packages/server dev` - Start server with hot reload
- `bun --cwd packages/server build` - Build server for production
- `bun --cwd packages/server start` - Start production server
- `bun --cwd packages/server lint` - Run ESLint check
- `bun --cwd packages/server typecheck` - Run TypeScript type checking

## Code Style
- **TypeScript**: Strict mode enabled across all packages
- **React**: Functional components with TypeScript interfaces/types
- **Styling**: Tailwind CSS v4 with PostCSS, organized with prettier-plugin-tailwindcss
- **Formatting**: Prettier with single quotes, 2-space indentation, arrow parens as-needed
- **Linting**: ESLint with TypeScript and React plugins
- **Imports**: Path aliases configured:
  - `@/*` → src directory
  - `+/*` → assets directory
  - `~/*` → public directory
- **Naming Conventions**:
  - PascalCase: Components, types, interfaces
  - camelCase: Functions, variables, methods
  - kebab-case: File names for components
- **Error Handling**: Structured try/catch blocks with proper logging

## Architecture

### Database Package
- **Technology**: Prisma ORM with PostgreSQL
- **Models**: Challenge, Checkpoint, Seed, Result
- **Purpose**: Shared database schema and client for all packages

### Server Package
- **Core Services**:
  - **tRPC Server**: Type-safe API with WebSocket subscriptions
  - **WebSocket Server**: Real-time client communication (port 7175)
  - **TCP Socket Server**: Ironmon game data ingestion (port 8080)
  - **Twitch Integration**: EventSub webhooks and API client
  - **OBS WebSocket**: Integration for overlay control
- **Event System**:
  - Built on Emittery for type-safe event handling
  - Domain-based event organization
  - Subscription helpers for categorized events
- **Key Features**:
  - Real-time Twitch chat processing
  - Emote data management and caching
  - Game state synchronization
  - Webhook validation and security

### Overlays Package
- **Framework**: React 19 with Vite
- **Routing**: TanStack Router with type-safe routes
- **State Management**: TanStack Query for server state
- **Real-time**: tRPC WebSocket subscriptions
- **Animations**: Framer Motion, Matter.js physics, Rive animations
- **Key Features**:
  - Dynamic overlay components
  - Real-time emote rain effects
  - Game state visualization
  - Responsive layouts with Tailwind CSS v4

## Environment Variables
- `DATABASE_URL`: PostgreSQL connection string
- `TWITCH_CLIENT_ID`: Twitch application client ID
- `TWITCH_CLIENT_SECRET`: Twitch application client secret
- `TWITCH_EVENTSUB_SECRET`: Secret for EventSub webhook validation
- `TWITCH_USER_ID`: Twitch user ID for channel subscriptions

## Docker Support
- `docker-compose.yml`: Orchestrates PostgreSQL and application services
- `Dockerfile`: Multi-stage build for production deployment
- Scripts adapted for Docker environment (e.g., `docker-cache-emotes.sh`)

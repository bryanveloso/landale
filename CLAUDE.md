# Landale Project Guidelines

## Project Overview

Landale is a personal streaming overlay system built with Bun, featuring real-time Twitch integration, game data processing, and animated overlays. This project is designed for local hosting on a home server (Mac Mini) and uses bleeding-edge technologies for experimentation and personal use. The system is designed to work within Open Broadcaster Software (OBS) as browser sources.

## Tech Stack

- **Runtime**: Bun (latest)
- **Frontend**: React 19 (RC), TanStack Router/Query, Vite, Tailwind CSS v4 (beta), Framer Motion, Matter.js, Rive
- **Backend**: tRPC, WebSocket, TCP sockets, Twitch EventSub/API
- **Database**: PostgreSQL with Prisma v6 (beta)
- **Development**: TypeScript (strict mode), ESLint, Prettier, Docker Compose
- **Hosting**: Local Mac Mini with Docker, accessed only via local network
- **Monitoring**: Health check endpoints, structured logging with Pino
- **Shared Types**: Monorepo with shared types package

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

### Shared Package

- **Purpose**: Shared types and utilities across all packages
- **Contents**: IronMON types, Twitch types, common utilities
- **Benefits**: Type consistency, reduced duplication

### Database Package

- **Technology**: Prisma ORM with PostgreSQL
- **Models**: Challenge, Checkpoint, Seed, Result (with performance indexes)
- **Purpose**: Shared database schema and client for all packages

### Server Package

- **Core Services**:
  - **tRPC Server**: Type-safe API with WebSocket subscriptions
  - **WebSocket Server**: Real-time client communication (port 7175) with auto-reconnection
  - **TCP Socket Server**: IronMON game data ingestion (port 8080)
  - **Twitch Integration**: EventSub webhooks and API client
  - **Health Check**: HTTP endpoint at `/health` for monitoring
- **Event System**:
  - Built on Emittery for type-safe event handling
  - Domain-based event organization (Twitch, IronMON)
  - Subscription helpers for categorized events
- **Key Features**:
  - Environment variable validation with Zod
  - Structured logging with Pino (optional)
  - Real-time Twitch chat processing
  - Emote data management and caching
  - Game state synchronization
  - Error handling with proper logging

### Overlays Package

- **Framework**: React 19 with Vite
- **Routing**: TanStack Router with type-safe routes
- **State Management**: TanStack Query for server state
- **Real-time**: tRPC WebSocket subscriptions with auto-reconnection
- **Animations**: Framer Motion, Matter.js physics, Rive animations
- **Key Features**:
  - Error boundaries to prevent stream crashes
  - React performance optimizations (memo, cleanup)
  - Dynamic overlay components
  - Real-time emote rain effects with physics
  - Game state visualization (IronMON)
  - Responsive layouts with Tailwind CSS v4
  - OBS browser source compatible

## Environment Variables

### Required
- `DATABASE_URL`: PostgreSQL connection string
- `TWITCH_CLIENT_ID`: Twitch application client ID
- `TWITCH_CLIENT_SECRET`: Twitch application client secret
- `TWITCH_EVENTSUB_SECRET`: Secret for EventSub webhook validation
- `TWITCH_USER_ID`: Twitch user ID for channel subscriptions

### Optional
- `NODE_ENV`: Environment (development/production)
- `LOG_LEVEL`: Logging level (error/warn/info/debug)
- `STRUCTURED_LOGGING`: Enable JSON logging (true/false)

## Docker Support

- `docker-compose.yml`: Orchestrates PostgreSQL and application services for local deployment
- `Dockerfile`: Build configuration for local Docker deployment
- Scripts adapted for Docker environment (e.g., `docker-cache-emotes.sh`)
- Designed for local network access only - no external hosting required

## Project Context

- **Personal Project**: Designed specifically for personal streaming setup
- **Local Hosting**: Runs on home Mac Mini server, not intended for cloud deployment
- **Bleeding Edge**: Intentionally uses latest/beta versions for experimentation
- **Security Model**: Relies on local network security, not exposed to internet
- **Git Ignored Files**: `twitch-token.json` and other sensitive files are properly gitignored

## Project Memories

- Please remember that this overlay is used within an Open Broadcaster System (OBS) context.
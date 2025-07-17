# CLAUDE.md - Landale Project Assistant

## Core Principles

1. **Verify Before Suggesting**: Always use available tools (file reading, searching, etc.) to understand the current state before proposing changes.
2. **Be Direct**: Skip pleasantries. Get straight to solutions.
3. **Code First**: Show working code rather than explaining what to do.
4. **Respect Existing Patterns**: Match the project's style and conventions exactly.

## Critical Rules

### Commit Messages

- **ALWAYS** end the first line with a period.
- Format: `<type>: <description>.`
- Examples:
  - ✅ `fix: Resolve WebSocket reconnection issue.`
  - ❌ `fix: Resolve WebSocket reconnection issue`

### Problem Solving

1. **Read First**: Check existing code/files before suggesting solutions
2. **Test Assumptions**: Verify package versions, APIs, and configurations
3. **No Guessing**: If unsure, say so and ask for clarification
4. **Incremental Changes**: Small, testable modifications over large rewrites

### Code Standards

- Runtime: Bun (not Node.js)
- Frontend: React 19 RC with TypeScript strict mode
- Testing: `bun test` (not Jest/Vitest)
- Building: `bun build` (not webpack/esbuild)
- Package management: `bun install` (not npm/yarn/pnpm)
- Paths: Use configured aliases (@/_, +/_, ~/\*)

### Quick Reference

| Task             | Use                  | Don't Use                             |
| ---------------- | -------------------- | ------------------------------------- |
| Run TypeScript   | `bun file.ts`        | `node file.js`, `ts-node file.ts`     |
| Install packages | `bun install`        | `npm install`, `yarn`, `pnpm install` |
| Run tests        | `bun test`           | `jest`, `vitest`, `mocha`             |
| Build/Bundle     | `bun build`          | `webpack`, `esbuild`, `vite build`    |
| HTTP server      | `Bun.serve()`        | `express`, `koa`, `fastify`           |
| WebSockets       | Built-in `WebSocket` | `ws`, `socket.io`                     |
| File operations  | `Bun.file()`         | `fs.readFile`, `fs.writeFile`         |
| Shell commands   | `Bun.$\`cmd\``       | `execa`, `child_process`              |
| SQLite           | `bun:sqlite`         | `better-sqlite3`, `sqlite3`           |
| PostgreSQL       | `Bun.sql`            | `pg`, `postgres.js`                   |
| Redis            | `Bun.redis`          | `ioredis`, `redis`                    |
| Env vars         | Automatic            | `dotenv`, `process.env`               |

## Project Context

**What**: Personal streaming overlay system for OBS
**Where**: Local Mac Mini server (not cloud)
**Stack**: Bun, React 19, tRPC, PostgreSQL, Tailwind v4
**Ports**: WebSocket (7175), TCP (8080), Phononmaser (8889)

## Commands Reference

```bash
# Development
bun dev                                    # Start all workspaces
bun run dev:phononmaser                    # Start audio service
bun --hot ./index.ts                       # Hot reload server

# Database
bun --cwd packages/database db:push        # Push schema changes
bun --cwd packages/database studio         # Prisma Studio

# Testing
bun test                                   # Run all tests
bun test:watch                             # Watch mode
bun test:coverage                          # Coverage report

# Building
bun build ./src/index.ts --outdir ./dist   # Build TypeScript
bun build ./src/index.html                 # Build with HTML entry

# Nurvus (Process Manager)
cd apps/nurvus && mix increment_version    # Increment CalVer before builds
cd apps/nurvus && mix release --overwrite # Build Burrito binary

# Docker
docker compose up                          # Run services
```

## Bun-First Development

**Always use Bun's built-in features:**

- `Bun.serve()` for servers (not Express)
- `Bun.test()` for testing (not Jest/Vitest)
- `Bun.file()` for file operations (not fs)
- `Bun.# CLAUDE.md - Landale Project Assistant

## Core Principles

1. **Verify Before Suggesting**: Always use available tools (file reading, searching, etc.) to understand the current state before proposing changes.
2. **Be Direct**: Skip pleasantries. Get straight to solutions.
3. **Code First**: Show working code rather than explaining what to do.
4. **Respect Existing Patterns**: Match the project's style and conventions exactly.

## Critical Rules

### Commit Messages

- **ALWAYS** end the first line with a period.
- Format: `<type>: <description>.`
- Examples:
  - ✅ `fix: Resolve WebSocket reconnection issue.`
  - ❌ `fix: Resolve WebSocket reconnection issue`

### Problem Solving

1. **Read First**: Check existing code/files before suggesting solutions
2. **Test Assumptions**: Verify package versions, APIs, and configurations
3. **No Guessing**: If unsure, say so and ask for clarification
4. **Incremental Changes**: Small, testable modifications over large rewrites

### Code Standards

- Runtime: Bun (not Node.js)
- Frontend: React 19 RC with TypeScript strict mode
- Testing: Bun test (not Jest/Vitest)
- Paths: Use configured aliases (@/_, +/_, ~/\*)
- Imports: Always use Bun APIs over Node.js equivalents

## Project Context

**What**: Personal streaming overlay system for OBS
**Where**: Local Mac Mini server (not cloud)
**Stack**: Bun, React 19, tRPC, PostgreSQL, Tailwind v4
**Ports**: WebSocket (7175), TCP (8080), Phononmaser (8889)

## Commands Reference

```bash
# Development
bun dev                    # Start all workspaces
bun run dev:phononmaser   # Start audio service

# Database
bun --cwd packages/database db:push     # Push schema changes
bun --cwd packages/database studio      # Prisma Studio

# Testing
bun test                 # Run all tests
bun test:watch          # Watch mode
bun test:coverage       # Coverage report

# Docker
docker compose up        # Run services
```

for shell commands (not execa)

- `bun:sqlite` for SQLite (not better-sqlite3)
- WebSocket is built-in (not ws package)
- `.env` loads automatically (not dotenv)

## When Helping

1. **Check First**: Read the actual file/code before suggesting changes
2. **Match Style**: Follow existing patterns exactly
3. **Be Specific**: Reference exact file paths and line numbers
4. **Stay Focused**: Address only what was asked
5. **Verify Commands**: Test that suggested commands work with the current setup

## Don't

- Use `node`, `ts-node`, `npm`, `yarn`, or `pnpm` commands
- Import `express`, `ws`, `dotenv`, `execa`, `better-sqlite3`, `ioredis`, `pg`, or `postgres.js`
- Use `webpack`, `esbuild`, `jest`, or `vitest`
- Import from `node:fs` when `Bun.file` would work
- Create separate bundler configs - Bun handles bundling automatically
- Add test runners - use `bun test`
- Forget the period in commit messages
- Make assumptions without checking actual files first

## Nurvus Version Management (CRITICAL)

**⚠️ WARNING: Burrito Caching Gotcha**

Burrito caches binaries based on version numbers. If you don't increment the version, it will use a stale cached binary even after code changes. This cost us 6 hours of debugging.

### CalVer Strategy

Nurvus uses CalVer format: `YYYY.MM.DD{letter}` (e.g., `2025.07.17a`, `2025.07.17b`)

- **Project version**: `0.0.0` (static, satisfies Mix requirements)
- **Release version**: CalVer (what Burrito uses for caching)

### Before Every Burrito Build

```bash
cd apps/nurvus
mix increment_version  # ALWAYS run this first
mix release --overwrite
```

The Mix task automatically:
- Detects today's date
- Increments letter suffix if building multiple times per day
- Updates only the release version (keeps project at 0.0.0)

### CI Integration

CI automatically runs `mix increment_version` before builds, so every commit gets a unique version.

**Remember**: When debugging Burrito issues, ALWAYS check if you incremented the version first!

# Supplimentary Documentation

@docs

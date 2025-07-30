# Overlay Directory Structure Guide

## Overview

This guide explains how to organize streaming overlay files for OBS browser sources. Each route becomes a separate browser source in OBS, so organization is critical for maintainability.

## Current Structure

```
src/
├── components/           # Reusable UI components
│   ├── ui/              # Basic UI elements (buttons, inputs, etc.)
│   ├── widgets/         # Stream-specific widgets (alerts, stats, etc.)
│   └── animated/        # Components with built-in animations
├── routes/              # OBS browser source routes
│   ├── base.tsx         # Universal alert layer (every scene)
│   ├── omnibar.tsx      # Priority messaging system
│   ├── takeover.tsx     # Full-screen interrupts
│   └── shows/           # Show-specific overlays
│       ├── variety/     # Default/variety show
│       ├── coding/      # Development streams
│       └── ironmon/     # IronMON challenge runs
├── hooks/               # Data and animation hooks
├── providers/           # Context providers (WebSocket, etc.)
├── config/              # Configuration files
└── utils/               # Helper functions and utilities
```

## Route vs Component Decision Framework

### When to Create a New Route

**Create a route when:**

- It needs to be a separate OBS browser source
- It has independent positioning/layering needs
- It handles different audio sources
- It has completely different layout requirements

**Examples:**

- `/base` - Universal alerts (every scene has this)
- `/shows/ironmon/main` - IronMON-specific layout
- `/emote-rain` - Full-screen particle effects
- `/takeover` - Full-screen interrupts

### When to Create a Component

**Create a component when:**

- It's reusable across multiple routes
- It's part of a larger layout
- It shares the same browser source
- It doesn't need independent positioning

**Examples:**

- `<AlertWidget />` - Used by `/base` route
- `<StatsDisplay />` - Used by multiple show routes
- `<EmoteCounter />` - Part of larger overlay layout

## Component Organization

### /components/ui/

Basic, unstyled UI building blocks:

```typescript
Button.tsx // Basic button component
Modal.tsx // Modal container
ProgressBar.tsx // Progress/health bars
Badge.tsx // Status badges
```

### /components/widgets/

Stream-specific, styled widgets:

```typescript
AlertDisplay.tsx // Alert notifications with animations
StatsCounter.tsx // Numeric stats display
RecentList.tsx // Recent events (follows, subs, etc.)
MediaFrame.tsx // Image/video containers
```

### /components/animated/

Components with built-in GSAP animations:

```typescript
SlideIn.tsx // Slide in/out wrapper
FadeTransition.tsx // Fade in/out wrapper
StaggerList.tsx // Staggered list animations
```

## Route Organization

### Universal Routes

Routes that work across all shows:

```typescript
/base               // Alerts, audio, universal features
/omnibar            // Priority messaging system
/takeover           // Full-screen interrupts
```

### Show-Specific Routes

Routes for specific streaming contexts:

```typescript
;/shows/aeirtvy /
  main / // Default show layout
  shows /
  coding /
  main / // Development streaming
  shows /
  ironmon /
  main // IronMON challenge layout
```

### Standalone Feature Routes

Routes for independent features:

```typescript
/emote-rain            // Full-screen emote effects
/chat-overlay          // Chat integration
/music-display         // Now playing (Rainwave)
```

## File Naming Conventions

### Routes

- Use kebab-case: `omnibar.tsx`, `takeover.tsx`
- Show routes: `shows/ironmon/main.tsx`
- Feature routes: `emote-rain.tsx`, `chat-overlay.tsx`

### Components

- Use PascalCase: `AlertDisplay.tsx`, `StatsCounter.tsx`
- Include index files for complex components: `AlertDisplay/index.tsx`
- Co-locate styles: `AlertDisplay/AlertDisplay.css`

### Hooks and Utils

- Use camelCase: `useStreamData.ts`, `useAnimation.ts`
- Prefix custom hooks: `use-stream-channel.tsx`

## OBS Scene Organization

### Basic Scene Structure

```
Scene: IronMON
├── Game Capture
├── Webcam
├── IronMON Main Overlay    (/shows/ironmon/main)
├── Universal Alerts        (/base)
└── Music Display          (/music-display)
```

### Layer Order Guidelines

1. **Game/Desktop Capture** (bottom)
2. **Show-specific overlay** (show content)
3. **Universal alerts** (important notifications)
4. **Takeover** (emergency full-screen)

## When to Create New Files

### New Show Type

When adding a new show (e.g., FFXIV):

1. Create `/shows/ffxiv/main.tsx`
2. Add show type to `config/layer-mappings.ts`
3. Create show-specific components in `/components/widgets/`
4. Add CSS variables for theming

### New Feature

When adding a new feature (e.g., subscriber goal):

1. **If universal**: Add to `/base` or create `/subscriber-goals.tsx`
2. **If show-specific**: Add component to show's main route
3. **If standalone**: Create `/subscriber-goals.tsx` route

### New Widget

When creating reusable widgets:

1. Create in `/components/widgets/`
2. Include TypeScript props interface
3. Support theming via CSS custom properties
4. Include animation utilities if needed

## Best Practices

### Keep Related Files Close

Store components, styles, and tests for the same feature together:

```
components/widgets/AlertDisplay/
├── index.tsx
├── AlertDisplay.tsx
├── AlertDisplay.css
└── AlertDisplay.test.tsx
```

### Separate Concerns

- **Routes**: Handle data fetching and layout
- **Components**: Handle rendering and interaction
- **Hooks**: Handle business logic and state
- **Utils**: Handle pure functions and helpers

### Feature-First Organization

Group by feature rather than file type when it makes sense:

```
features/alerts/
├── AlertDisplay.tsx
├── AlertSound.ts
├── alert-animations.ts
└── use-alert-queue.ts
```

This structure scales from simple variety shows to complex data-dense overlays while maintaining clear separation of concerns and OBS compatibility.

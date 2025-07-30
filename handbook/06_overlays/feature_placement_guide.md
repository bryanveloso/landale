# Feature Placement Guide

## Overview

This guide establishes patterns for positioning streaming features within overlay layouts. It provides guidelines for where different types of content should be placed for optimal viewer experience and OBS integration.

## Placement Hierarchy

### Priority-Based Positioning

Features are positioned based on their priority and urgency:

**Priority 1 - Critical (Foreground Layer)**

- **Position**: Center screen, full attention
- **Content**: Death alerts, emergency announcements, raid alerts
- **Duration**: 3-8 seconds maximum
- **Examples**: IronMON death, stream failure, emergency override

**Priority 2 - Important (Midground Layer)**

- **Position**: Upper-center or center, prominent but not overwhelming
- **Content**: Celebrations, achievements, milestones
- **Duration**: 5-15 seconds
- **Examples**: Sub trains, level ups, follower celebrations

**Priority 3 - Ambient (Background Layer)**

- **Position**: Bottom or side edges, persistent display
- **Content**: Statistics, recent activity, stream goals
- **Duration**: Persistent or slow rotation
- **Examples**: Viewer count, recent follows, emote stats

## Positioning Patterns by Content Type

### Alert Content (Priority 1)

**Positioning Guidelines:**

```css
.content-alert {
  /* Center screen positioning */
  position: fixed;
  top: 40%;
  left: 50%;
  transform: translate(-50%, -50%);

  /* Full attention styling */
  min-width: 600px;
  max-width: 1200px;
  z-index: 1000;
}
```

**Best Practices:**

- Center horizontally and vertically
- Large enough to read clearly
- Brief, impactful display duration
- High contrast colors for visibility
- Animation draws attention without being distracting

### Celebration Content (Priority 2)

**Positioning Guidelines:**

```css
.content-celebration {
  /* Upper-center positioning */
  position: fixed;
  top: 25%;
  left: 50%;
  transform: translate(-50%, -50%);

  /* Prominent but not overwhelming */
  min-width: 400px;
  max-width: 800px;
  z-index: 500;
}
```

**Best Practices:**

- Upper portion of screen to avoid blocking game content
- Moderate size for celebration without overwhelming
- Festive animations that enhance the moment
- Duration allows appreciation without blocking too long

### Statistics Content (Priority 3)

**Positioning Guidelines:**

```css
.content-stats {
  /* Bottom positioning for persistence */
  position: fixed;
  bottom: 2rem;
  left: 2rem;

  /* Compact, non-intrusive sizing */
  max-width: 300px;
  z-index: 100;
}
```

**Best Practices:**

- Bottom or side edges to avoid blocking content
- Compact, readable design
- Subtle animations that don't distract
- Persistent display or slow rotation

## Show-Specific Placement Patterns

### Component-Based Positioning (Tailwind v4 Approach)

Following Tailwind v4 best practices, use utility classes in components rather than extracting to CSS:

```typescript
// IronMON death alert component
function DeathAlert() {
  return (
    <div class="fixed top-[45%] left-1/2 -translate-x-1/2 -translate-y-1/2 text-4xl bg-red-600/90 text-white p-6 rounded-lg z-100">
      {/* Death alert content */}
    </div>
  )
}

// IronMON run stats component
function RunStats() {
  return (
    <div class="fixed bottom-8 left-8 flex flex-col gap-2 max-w-80 z-10">
      {/* Run statistics */}
    </div>
  )
}

// Variety raid alert component
function RaidAlert() {
  return (
    <div class="fixed top-2/5 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-purple-600/90 text-white p-4 rounded-lg z-100">
      {/* Raid alert content */}
    </div>
  )
}
```

### Essential CSS for Data Attributes Only

Keep minimal CSS for state-based styling that can't be handled with utilities:

```css
/* Essential positioning for content types in styles.css */
[data-content-type='death-alert'] {
  position: fixed;
  top: 45%;
  left: 50%;
  transform: translate(-50%, -50%);
  z-index: 100;
}

[data-content-type='run-stats'] {
  position: fixed;
  bottom: var(--spacing-8);
  left: var(--spacing-8);
  z-index: 10;
}

[data-content-type='raid-alert'] {
  position: fixed;
  top: 40%;
  left: 50%;
  transform: translate(-50%, -50%);
  z-index: 100;
}

/* Show-specific theming via CSS custom properties */
[data-show='ironmon'] [data-content-type='death-alert'] {
  background: var(--color-red-600/90);
  color: white;
}

[data-show='variety'] [data-content-type='raid-alert'] {
  background: var(--color-purple-600/90);
  color: white;
}

[data-show='coding'] [data-content-type='build-failure'] {
  background: var(--color-red-600/90);
  color: white;
}
```

## Responsive Canvas Guidelines

### Standard Canvas Dimensions

All positioning relative to 1920x1080 overlay space:

```css
:root {
  --canvas-width: 1920px;
  --canvas-height: 1080px;

  /* Safe zones for content */
  --safe-zone-top: 10%;
  --safe-zone-bottom: 10%;
  --safe-zone-left: 5%;
  --safe-zone-right: 5%;
}
```

### Safe Zone Positioning

Avoid placing content too close to edges:

```css
.feature-placement {
  /* Respect safe zones */
  min-height: calc(var(--canvas-height) * 0.8);
  min-width: calc(var(--canvas-width) * 0.9);

  /* Center within safe area */
  top: var(--safe-zone-top);
  left: var(--safe-zone-left);
  right: var(--safe-zone-right);
  bottom: var(--safe-zone-bottom);
}
```

## Animation-Based Positioning

### Entry Animations

Features enter from appropriate directions based on final position:

```typescript
// Center content - scale from center
gsap.fromTo(centerElement, { scale: 0.8, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.4 })

// Bottom content - slide up
gsap.fromTo(bottomElement, { y: 50, opacity: 0 }, { y: 0, opacity: 1, duration: 0.4 })

// Side content - slide in from edge
gsap.fromTo(sideElement, { x: -100, opacity: 0 }, { x: 0, opacity: 1, duration: 0.4 })
```

### Layer Interruption Positioning

When higher priority content appears, lower priority content gets repositioned:

```typescript
// Midground interruption - move down slightly
gsap.to(midgroundElement, {
  y: 30,
  scale: 0.95,
  opacity: 0.7,
  duration: 0.3
})

// Background interruption - move down more
gsap.to(backgroundElement, {
  y: 60,
  scale: 0.9,
  opacity: 0.5,
  duration: 0.3
})
```

## OBS Scene Positioning

### Browser Source Layer Order

Position overlay browser sources in this order (top to bottom):

```
1. Takeover Layer     - Full screen emergency overlays
2. Base Layer         - Universal alerts (center positioning)
3. Show Overlay       - Show-specific layout (mixed positioning)
4. Music Display      - Independent positioning
5. Webcam            - Fixed position
6. Game Capture      - Background content
```

### Independent Feature Positioning

Some features get their own browser sources for independent positioning:

**Chat Overlay** (`/chat-overlay`)

- Position: Right side of screen
- Size: 400x800px
- OBS Position: X: 1520, Y: 140

**Music Display** (`/music-display`)

- Position: Bottom right corner
- Size: 350x150px
- OBS Position: X: 1570, Y: 930

**Emote Rain** (`/emote-rain`)

- Position: Full screen overlay
- Size: 1920x1080px
- OBS Position: X: 0, Y: 0

## Content-Specific Placement Rules

### Text-Heavy Content

**Guidelines:**

- Larger font sizes for readability
- High contrast backgrounds
- Centered or left-aligned text
- Avoid bottom 20% for readability

```css
.text-heavy-content {
  font-size: 1.5rem;
  line-height: 1.4;
  background: rgba(0, 0, 0, 0.8);
  color: white;
  padding: 1.5rem;
  border-radius: 0.5rem;
}
```

### Image/Media Content

**Guidelines:**

- Maintain aspect ratios
- Use safe zones for positioning
- Consider background content when sizing

```css
.media-content {
  max-width: 40vw;
  max-height: 30vh;
  object-fit: contain;
  border-radius: 0.5rem;
}
```

### List Content

**Guidelines:**

- Vertical lists on sides
- Horizontal lists on bottom
- Scrollable when content exceeds space
- Staggered animations for entries

```css
.list-content {
  max-height: 300px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.list-item {
  padding: 0.5rem;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 0.25rem;
}
```

## Feature Placement Decision Tree

```
Is this content critical/emergency?
├── Yes → Center screen, foreground layer
└── No → Is this a celebration/achievement?
    ├── Yes → Upper-center, midground layer
    └── No → Is this persistent information?
        ├── Yes → Bottom/side edges, background layer
        └── No → Consider if this needs its own route
```

## Best Practices

### 1. Readability First

```css
/* Always ensure text is readable */
.feature-content {
  /* High contrast */
  color: white;
  background: rgba(0, 0, 0, 0.8);

  /* Readable font sizes */
  font-size: clamp(1rem, 2vw, 2rem);

  /* Sufficient padding */
  padding: 1rem 1.5rem;
}
```

### 2. Non-Intrusive Persistence

```css
/* Background content should not distract */
.persistent-content {
  opacity: 0.8;
  font-size: 0.875rem;
  background: rgba(0, 0, 0, 0.6);
  transition: opacity 0.3s ease;
}

.persistent-content:hover {
  opacity: 1;
}
```

### 3. Animation Respect

```typescript
// Animations should enhance, not distract
const subtleEntry = gsap.fromTo(element, { y: 20, opacity: 0 }, { y: 0, opacity: 1, duration: 0.4, ease: 'power2.out' })

// Avoid overly flashy animations for persistent content
```

### 4. Context Awareness (Tailwind v4 Approach)

Use utility classes in components for show-specific positioning:

```typescript
// Show-aware component positioning
function StatsDisplay({ show }: { show: string }) {
  const baseClasses = "fixed flex flex-col gap-2"

  const showClasses = {
    ironmon: "bottom-16 left-8 w-80", // More room for game stats
    variety: "bottom-8 right-8 w-52", // Compact display
    coding: "bottom-8 left-1/2 -translate-x-1/2 w-64" // Centered
  }

  return (
    <div class={`${baseClasses} ${showClasses[show] || showClasses.variety}`}>
      {/* Stats content */}
    </div>
  )
}
```

### 5. Performance Considerations

Follow Tailwind v4 performance best practices:

```typescript
// Good - GPU accelerated transforms with utilities
<div class="transform translate-y-0 transition-transform duration-300 ease-out">
  <div class="hidden:translate-y-full">Content</div>
</div>

// Good - Use Tailwind utilities for animations
<div class="animate-fade-in-up">
  {/* GSAP handles complex animations, Tailwind for simple ones */}
</div>
```

```css
/* Essential CSS - only for complex state management */
[data-state='entering'] {
  transform: translateY(20px);
  opacity: 0;
  transition: all 0.3s ease-out;
}

[data-state='active'] {
  transform: translateY(0);
  opacity: 1;
}

/* Avoid layout-triggering properties in CSS */
/* Use transform instead of top/left/bottom/right */
```

This guide ensures consistent, readable, and performant feature placement across all streaming overlay scenarios while maintaining professional presentation and optimal viewer experience.

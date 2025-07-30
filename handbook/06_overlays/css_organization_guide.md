# CSS Organization Guide for Tailwind v4

## Overview

This guide explains how to organize CSS in the overlays app following Tailwind v4 best practices. The approach uses minimal, focused CSS modules for data attribute styling while keeping utility classes in components.

## Architecture Principles

### 1. Utility-First in Components

Following Tailwind v4 guidelines:

- Use utility classes directly in SolidJS components
- Never use `@apply` directive (deprecated in v4)
- Extract repeated patterns into framework components, not CSS

### 2. Minimal CSS for Complex State

Use CSS only for:

- Data attribute selectors for state management
- Complex animations that require keyframes
- Dynamic theming via CSS custom properties

### 3. Modular CSS Organization

Break CSS into focused modules imported into main styles file:

- `styles.css` - Main entry point with theme and imports
- `styles/layers.css` - Layer orchestrator state styling
- `styles/animations.css` - Animation keyframes and variables

## File Structure

```
src/
├── styles.css                    # Main styles with imports
└── styles/
    ├── layers.css                # Layer orchestrator styling
    ├── animations.css            # Animation keyframes
    └── [future-modules.css]      # Additional focused modules
```

## Current Implementation

### styles.css (Main Entry Point)

```css
@import 'tailwindcss';

/* Import focused CSS modules */
@import './styles/layers.css';
@import './styles/animations.css';

@theme {
  /* Custom color palette */
  /* Custom dimensions for OBS canvas */
  /* Layer orchestrator spacing */
}

:root {
  /* Base font and rendering settings */
}

/* Minimal base styles */
.overlay-container {
  width: var(--width-canvas);
  height: var(--height-canvas);
  position: relative;
  overflow: hidden;
}
```

### styles/layers.css (Layer Orchestrator)

Handles all layer orchestrator state management:

```css
/* Layer State Management */
[data-state='entering'] {
  /* entrance styles */
}
[data-state='active'] {
  /* active styles */
}
[data-state='interrupted'] {
  /* interrupted styles */
}
[data-state='exiting'] {
  /* exit styles */
}

/* Priority-Based Z-Index */
[data-priority='100'] {
  z-index: 100;
}
[data-priority='50'] {
  z-index: 50;
}
[data-priority='10'] {
  z-index: 10;
}

/* Content Type Positioning */
[data-content-type='alert'] {
  /* alert positioning */
}
[data-content-type='celebration'] {
  /* celebration positioning */
}
[data-content-type='stats'] {
  /* stats positioning */
}

/* Show-Specific Theming */
[data-show='ironmon'] {
  /* IronMON theme variables */
}
[data-show='variety'] {
  /* variety theme variables */
}
[data-show='coding'] {
  /* coding theme variables */
}
```

### styles/animations.css (Animations)

Animation-specific CSS variables and keyframes:

```css
/* Animation Duration Variables */
:root {
  --duration-fast: 0.2s;
  --duration-normal: 0.4s;
  --duration-slow: 0.6s;
  --ease-out-back: cubic-bezier(0.34, 1.56, 0.64, 1);
}

/* Animation Keyframes */
@keyframes fadeIn {
  /* fade animation */
}
@keyframes slideUp {
  /* slide animation */
}
@keyframes alertEntrance {
  /* alert-specific animation */
}

/* Data Attribute Animation Classes */
[data-animation='fade-in'] {
  animation: fadeIn var(--duration-normal) var(--ease-out-quart);
}
```

## Component Styling Approach

### ✅ Good: Utility Classes in Components

```typescript
function AlertDisplay({ type, content }: AlertProps) {
  return (
    <div
      class="fixed top-2/5 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-red-600/90 text-white p-4 rounded-lg z-100"
      data-content-type="alert"
      data-state="active"
    >
      {content}
    </div>
  )
}
```

### ✅ Good: Dynamic Classes with Show Context

```typescript
function StatsDisplay({ show }: { show: string }) {
  const showClasses = {
    ironmon: "bottom-16 left-8 w-80",
    variety: "bottom-8 right-8 w-52",
    coding: "bottom-8 left-1/2 -translate-x-1/2 w-64"
  }

  return (
    <div
      class={`fixed flex flex-col gap-2 ${showClasses[show]}`}
      data-show={show}
      data-content-type="stats"
    >
      {/* Stats content */}
    </div>
  )
}
```

### ❌ Avoid: Extracting Utilities to CSS

```css
/* Don't do this - violates Tailwind v4 best practices */
.alert-positioning {
  @apply fixed top-2/5 left-1/2 -translate-x-1/2 -translate-y-1/2;
}
```

## When to Add New CSS Files

### Create a New CSS Module When:

1. **Complex State Management** - Multiple data attribute selectors for a specific feature
2. **Animation Keyframes** - Custom animations that can't be handled with utilities
3. **Theme Variables** - CSS custom properties for dynamic theming
4. **OBS-Specific Styling** - Overlay positioning that can't use utilities

### Examples of Valid New Modules:

```
styles/
├── layers.css        # ✅ Layer orchestrator states
├── animations.css    # ✅ Animation keyframes
├── obs-browser.css   # ✅ OBS browser source specific styles
├── debug.css         # ✅ Development debugging styles
└── chat-overlay.css  # ✅ Chat-specific positioning/animations
```

### ❌ Avoid Creating Modules For:

- Component-specific utility combinations
- Simple positioning that can use utilities
- Color variations (use CSS custom properties instead)
- Responsive breakpoints (use Tailwind utilities)

## Best Practices

### 1. Minimal CSS Surface Area

Keep CSS files focused and minimal:

```css
/* Good - focused on essential data attributes */
[data-state='entering'] {
  opacity: 0;
  transform: translateY(20px);
  transition: all 0.4s ease-out;
}

/* Avoid - utility combinations that belong in components */
.modal-content {
  padding: 1rem;
  background: white;
  border-radius: 0.5rem;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
}
```

### 2. Use CSS Custom Properties for Theming

```css
/* Good - dynamic theming */
[data-show='ironmon'] {
  --layer-accent: var(--color-red-500);
  --layer-bg: var(--color-red-500/10);
}

[data-content-type='alert'] {
  background: var(--layer-accent, var(--color-purple-500));
  border: 2px solid var(--layer-accent);
}
```

### 3. Leverage Tailwind v4 CSS Variables

Access theme values in CSS:

```css
.custom-element {
  background: var(--color-red-500);
  padding: var(--spacing-4);
  border-radius: var(--radius-lg);
  margin-top: calc(100vh - var(--spacing-16));
}
```

### 4. Performance Considerations

```css
/* Good - GPU accelerated properties */
[data-state='entering'] {
  transform: translateY(20px);
  opacity: 0;
}

/* Avoid - layout-triggering properties */
[data-state='entering'] {
  top: 20px;
  height: 200px;
}
```

## Import Order

Maintain consistent import order in styles.css:

```css
/* 1. Tailwind CSS import */
@import 'tailwindcss';

/* 2. CSS modules (order by specificity) */
@import './styles/layers.css';      # Core layer system
@import './styles/animations.css';  # Animation support
@import './styles/debug.css';       # Development helpers

/* 3. Theme configuration */
@theme {
  /* Theme variables */
}

/* 4. Root styles */
:root {
  /* Base styles */
}

/* 5. Minimal utility classes */
.overlay-container {
  /* Essential base classes only */
}
```

## Migration from Class-Based CSS

When converting existing CSS to Tailwind v4 approach:

### Step 1: Identify Utility Combinations

```css
/* Before */
.alert-box {
  position: fixed;
  top: 40%;
  left: 50%;
  transform: translate(-50%, -50%);
  padding: 1rem;
  background: rgba(239, 68, 68, 0.9);
  border-radius: 0.5rem;
}
```

### Step 2: Move to Component

```typescript
// After
function AlertBox() {
  return (
    <div class="fixed top-2/5 left-1/2 -translate-x-1/2 -translate-y-1/2 p-4 bg-red-600/90 rounded-lg">
      {/* Alert content */}
    </div>
  )
}
```

### Step 3: Keep Complex State in CSS

```css
/* Keep in CSS - complex state management */
[data-state='entering'] {
  animation: complexAlertEntrance 0.5s ease-out;
}

@keyframes complexAlertEntrance {
  0% {
    opacity: 0;
    transform: translate(-50%, -50%) scale(0.8) rotate(-5deg);
  }
  60% {
    transform: translate(-50%, -50%) scale(1.05) rotate(1deg);
  }
  100% {
    opacity: 1;
    transform: translate(-50%, -50%) scale(1) rotate(0deg);
  }
}
```

## File Size Management

Keep individual CSS modules focused and small:

- **layers.css**: ~200 lines (layer states, positioning, theming)
- **animations.css**: ~150 lines (keyframes, animation variables)
- **debug.css**: ~50 lines (development helpers)

If a module exceeds ~250 lines, consider splitting by feature:

- `layers-states.css` (state management)
- `layers-positioning.css` (content positioning)
- `layers-theming.css` (show-specific themes)

This organization maintains Tailwind v4 best practices while keeping CSS modular and maintainable.

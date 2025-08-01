# Overlay Component Architecture

## Overview

The overlay components follow a clean architecture pattern that separates business logic from presentation. This makes it easy to style components without being overwhelmed by the underlying complexity.

## Architecture Layers

### 1. Hooks (`hooks/`)

- **Purpose**: Encapsulate all business logic, state management, and WebSocket communication
- **Example**: `useOmnibar()` manages layer orchestration, content prioritization, and state
- **Returns**: Pure data and actions, no JSX

### 2. Primitives (`components/primitives/`)

- **Purpose**: Unstyled, headless components that handle structure and accessibility
- **Example**: `OmnibarRoot`, `OmnibarLayer`, `ConnectionIndicator`
- **Characteristics**:
  - Accept signal accessors for reactivity
  - Use render props for flexible composition
  - No styling, only semantic HTML

### 3. Components (`components/`)

- **Purpose**: Compose primitives with hooks to create functional components
- **Example**: `OmnibarClean` uses `useOmnibar` hook with primitive components
- **Characteristics**:
  - Minimal logic (just composition)
  - Clean, readable structure
  - Easy to style

## Example: Omnibar Abstraction

### Before (Mixed Concerns)

```tsx
export function Omnibar() {
  // WebSocket logic
  const { streamState, isConnected } = useStreamChannel()

  // Orchestration logic
  const orchestrator = useLayerOrchestrator({...})

  // Complex state calculations
  createEffect(() => {
    // 50+ lines of prioritization logic
  })

  // Rendering mixed with logic
  return (
    <Show when={isVisible()}>
      <div class="omnibar" data-show={...}>
        {/* Complex nested components */}
      </div>
    </Show>
  )
}
```

### After (Clean Separation)

```tsx
export function Omnibar() {
  const omnibar = useOmnibar() // All logic encapsulated

  return (
    <OmnibarRoot show={omnibar.isVisible} rootProps={{...}}>
      <For each={['foreground', 'midground', 'background']}>
        {(layer) => (
          <OmnibarLayer {...omnibar.layers[layer]}>
            {(content) => <LayerRenderer content={content} />}
          </OmnibarLayer>
        )}
      </For>
    </OmnibarRoot>
  )
}
```

## Benefits

1. **Clean DX for Styling**: When you're ready to style, you only deal with simple components
2. **Testability**: Business logic in hooks can be tested independently
3. **Reusability**: Primitives can be styled differently for different contexts
4. **Maintainability**: Clear separation of concerns
5. **Performance**: Signal accessors passed down efficiently

## Styling Strategies

When you're ready to style, you have several options:

### 1. Direct Styling

Add classes directly to the primitives:

```tsx
<OmnibarRoot class="my-custom-styles" />
```

### 2. Styled Wrappers

Create styled versions:

```tsx
export function StyledOmnibarRoot(props) {
  return (
    <OmnibarRoot
      {...props}
      rootProps={{
        class: 'omnibar-styled animate-slide-up',
        ...props.rootProps
      }}
    />
  )
}
```

### 3. CSS Modules/Tailwind

The primitives work perfectly with any styling solution.

## Migration Path

1. The original `Omnibar` component is preserved at `components/omnibar-legacy.tsx`
2. The new abstracted version is at `components/omnibar.tsx`
3. Routes use the new abstracted version by default
4. To switch back: change import from `omnibar` to `omnibar-legacy`

## Next Steps

This pattern can be applied to other complex overlays:

- Stream notifications
- Chat overlays
- Alert systems
- Statistics displays

Each would follow the same pattern: Hook → Primitives → Clean Component

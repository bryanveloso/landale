/**
 * Telemetry Drawer Hook
 *
 * Manages the state and keyboard shortcuts for the telemetry drawer.
 */

import { createSignal, onMount, onCleanup } from 'solid-js'

export function useTelemetryDrawer() {
  const [isOpen, setIsOpen] = createSignal(false)

  const toggle = () => setIsOpen((prev) => !prev)
  const open = () => setIsOpen(true)
  const close = () => setIsOpen(false)

  // Handle keyboard shortcut (Ctrl/Cmd + Shift + T)
  const handleKeyDown = (e: KeyboardEvent) => {
    const isModifier = e.ctrlKey || e.metaKey // Support both Ctrl and Cmd

    if (isModifier && e.shiftKey && e.key === 'T') {
      e.preventDefault()
      toggle()
    }
  }

  onMount(() => {
    document.addEventListener('keydown', handleKeyDown)
  })

  onCleanup(() => {
    document.removeEventListener('keydown', handleKeyDown)
  })

  return {
    isOpen,
    toggle,
    open,
    close,
    setIsOpen
  }
}

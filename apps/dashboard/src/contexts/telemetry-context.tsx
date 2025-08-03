/**
 * Telemetry Context
 *
 * Provides shared telemetry drawer state across components.
 */

import { createContext, useContext } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { useTelemetryDrawer } from '@/hooks/use-telemetry-drawer'

interface TelemetryContextValue {
  isOpen: () => boolean
  toggle: () => void
  open: () => void
  close: () => void
}

const TelemetryContext = createContext<TelemetryContextValue>()

export const TelemetryProvider: Component<{ children: JSX.Element }> = (props) => {
  const telemetryDrawer = useTelemetryDrawer()

  return <TelemetryContext.Provider value={telemetryDrawer}>{props.children}</TelemetryContext.Provider>
}

export const useTelemetry = () => {
  const context = useContext(TelemetryContext)
  if (!context) {
    throw new Error('useTelemetry must be used within TelemetryProvider')
  }
  return context
}

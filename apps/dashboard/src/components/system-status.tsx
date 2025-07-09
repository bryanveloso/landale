/**
 * System Status Component
 * 
 * Displays comprehensive system context information for the dashboard.
 * Shows current show, priority level, and active content status.
 */

import { useLayerState } from '@/hooks/use-layer-state'

export function SystemStatus() {
  const { layerState } = useLayerState()

  const currentShow = () => layerState().current_show
  const priorityLevel = () => layerState().priority_level
  const activeContent = () => layerState().active_content
  const interruptCount = () => layerState().interrupt_stack.length

  const formatShow = (show: string) => {
    switch (show) {
      case 'ironmon': return 'IronMON'
      case 'variety': return 'Variety'
      case 'coding': return 'Coding'
      default: return show
    }
  }

  const formatPriority = (priority: string) => {
    switch (priority) {
      case 'alert': return 'Alert'
      case 'sub_train': return 'Sub Train'
      case 'ticker': return 'Ticker'
      default: return priority
    }
  }

  const formatContent = () => {
    const active = activeContent()
    const interrupts = interruptCount()
    
    if (active) {
      return `Active: ${active.type}`
    } else if (interrupts > 0) {
      return `Queue: ${interrupts}`
    } else {
      return 'None'
    }
  }

  return (
    <div class="system-status">
      <div class="show-indicator">
        Show: {formatShow(currentShow())}
      </div>
      <div class="priority-indicator">
        Priority: {formatPriority(priorityLevel())}
      </div>
      <div class="content-indicator">
        Content: {formatContent()}
      </div>
    </div>
  )
}
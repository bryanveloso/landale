import { useOBS } from '@/lib/obs-detection'
import { useDisplay } from '@/hooks/use-display'

export function DebugPanel() {
  const obsInfo = useOBS()
  const { isConnected } = useDisplay('statusBar')

  // Only show in browser, not in OBS
  if (obsInfo.isOBS) {
    return null
  }

  return (
    <div className="fixed bottom-4 left-4 max-w-sm space-y-2 rounded-lg bg-black/80 p-4 font-mono text-xs text-white">
      <div className="font-bold text-yellow-400">Debug Panel (Browser Only)</div>

      <div className="space-y-1">
        <div>Environment: Browser</div>
        <div>OBS Version: {obsInfo.version || 'N/A'}</div>
        <div>Platform: {obsInfo.platform || 'Unknown'}</div>
        <div>Connected: {isConnected ? 'Yes' : 'No'}</div>
        <div>
          Window: {window.innerWidth}x{window.innerHeight}
        </div>
        <div>Device Pixel Ratio: {window.devicePixelRatio}</div>
      </div>

      <div className="border-t border-gray-700 pt-2">
        <div className="text-gray-400">
          This panel is only visible in browser.
          <br />
          It will be hidden in OBS.
        </div>
      </div>
    </div>
  )
}

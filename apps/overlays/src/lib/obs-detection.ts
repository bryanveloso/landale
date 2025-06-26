/**
 * OBS Browser Source Detection Utilities
 */

import { useState, useEffect } from 'react'

export interface OBSInfo {
  isOBS: boolean
  version?: string
  platform?: string
  browserVersion?: string
}

/**
 * Detects if the current environment is OBS Browser Source
 * OBS CEF includes "OBS" in the user agent string
 */
export function detectOBS(): OBSInfo {
  const userAgent = navigator.userAgent

  // OBS Studio pattern: "... OBS/version ..."
  const obsMatch = userAgent.match(/OBS\/(\S+)/)

  if (obsMatch) {
    // Extract Chrome/CEF version if available
    const chromeMatch = userAgent.match(/Chrome\/(\S+)/)

    // Extract platform
    let platform: string | undefined
    if (userAgent.includes('Windows')) platform = 'windows'
    else if (userAgent.includes('Mac')) platform = 'mac'
    else if (userAgent.includes('Linux')) platform = 'linux'

    return {
      isOBS: true,
      version: obsMatch[1],
      platform,
      browserVersion: chromeMatch?.[1]
    }
  }

  return { isOBS: false }
}

/**
 * React hook for OBS detection
 */
export function useOBS(): OBSInfo {
  const [obsInfo, setOBSInfo] = useState<OBSInfo>({ isOBS: false })

  useEffect(() => {
    setOBSInfo(detectOBS())
  }, [])

  return obsInfo
}

/**
 * Simple boolean check for OBS
 */
export const isOBS = (): boolean => detectOBS().isOBS

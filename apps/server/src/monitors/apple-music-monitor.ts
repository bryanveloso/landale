#!/usr/bin/env bun

/**
 * Apple Music Monitor - Host Service
 * Runs on Mac Mini host, monitors Music.app via AppleScript
 * Sends updates to Docker container via WebSocket
 */

import { exec } from 'child_process'
import { WebSocket } from 'ws'
import { promisify } from 'util'
import { writeFileSync, unlinkSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'

const execAsync = promisify(exec)

// Configuration
const SERVER_URL = process.env.LANDALE_SERVER_URL || 'ws://localhost:7175'
const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || '1000', 10)

// AppleScript to get current track info
const APPLESCRIPT = `
tell application "Music"
  try
    if player state is playing then
      set currentTrack to current track
      set trackName to name of currentTrack
      set trackArtist to artist of currentTrack
      set trackAlbum to album of currentTrack
      set trackDuration to duration of currentTrack
      set playerPosition to player position
      
      return "playing|" & trackName & "|" & trackArtist & "|" & trackAlbum & "|" & trackDuration & "|" & playerPosition
    else if player state is paused then
      set currentTrack to current track
      set trackName to name of currentTrack
      set trackArtist to artist of currentTrack
      set trackAlbum to album of currentTrack
      set trackDuration to duration of currentTrack
      set playerPosition to player position
      
      return "paused|" & trackName & "|" & trackArtist & "|" & trackAlbum & "|" & trackDuration & "|" & playerPosition
    else
      return "stopped||||"
    end if
  on error
    return "stopped||||"
  end try
end tell
`

// Types
interface TrackInfo {
  playbackState: string
  currentSong: {
    title: string
    artist: string
    album: string
    duration: number
    playbackTime: number
  }
}

// Track current state to avoid unnecessary updates
let lastState: string | null = null
let ws: WebSocket | null = null
let reconnectTimer: NodeJS.Timeout | null = null
let monitorInterval: NodeJS.Timeout | null = null

async function getCurrentTrack(): Promise<TrackInfo | null> {
  try {
    // Write script to temp file to avoid shell escaping issues
    const scriptPath = join(tmpdir(), 'apple-music-check.scpt')
    writeFileSync(scriptPath, APPLESCRIPT)

    const { stdout } = await execAsync(`osascript ${scriptPath}`)

    // Clean up temp file
    unlinkSync(scriptPath)

    const parts = stdout.trim().split('|')

    if (parts[0] === 'stopped' || parts.length < 6) {
      return null
    }

    return {
      playbackState: parts[0]!,
      currentSong: {
        title: parts[1] || 'Unknown',
        artist: parts[2] || 'Unknown',
        album: parts[3] || 'Unknown',
        duration: parseFloat(parts[4] || '0') || 0,
        playbackTime: parseFloat(parts[5] || '0') || 0
      }
    }
  } catch (error) {
    // Music app might not be running
    if (error instanceof Error && error.message.includes('(-1728)')) {
      console.log('Music app is not running')
      return null
    }
    console.error('AppleScript error:', error instanceof Error ? error.message : String(error))
    return null
  }
}

function connectWebSocket(): void {
  if (ws && ws.readyState === WebSocket.OPEN) {
    return
  }

  console.log(`🔌 Connecting to ${SERVER_URL}...`)

  ws = new WebSocket(SERVER_URL)

  ws.on('open', () => {
    console.log('✅ WebSocket connected!')

    // Clear any reconnect timer
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }

    // Start monitoring
    startMonitoring()
  })

  ws.on('close', () => {
    console.log('❌ WebSocket disconnected')

    // Stop monitoring
    if (monitorInterval) {
      clearInterval(monitorInterval)
      monitorInterval = null
    }

    // Schedule reconnect
    reconnectTimer = setTimeout(() => {
      console.log('🔄 Attempting to reconnect...')
      connectWebSocket()
    }, 5000)
  })

  ws.on('error', (error: Error) => {
    console.error('WebSocket error:', error.message)
  })

  ws.on('message', (data: Buffer) => {
    // Handle any messages from server if needed
    const message = JSON.parse(data.toString())
    if (message.id && message.id === 1) {
      // This is the subscription confirmation
      console.log('📡 Subscription confirmed')
    }
  })
}

function sendUpdate(data: TrackInfo | { playbackState: string }): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    console.log('WebSocket not connected, skipping update')
    return
  }

  const message = {
    id: 1,
    method: 'mutation',
    params: {
      path: 'appleMusic.updateFromHost',
      input: data || { playbackState: 'stopped' }
    }
  }

  ws.send(JSON.stringify(message))
}

async function monitor(): Promise<void> {
  try {
    const trackInfo = await getCurrentTrack()

    // Only send update if state changed
    const currentState = JSON.stringify(trackInfo)
    if (currentState !== lastState) {
      console.log('Track state changed:', trackInfo)

      const updateData = trackInfo || { playbackState: 'stopped' }

      sendUpdate(updateData)
      lastState = currentState
    }
  } catch (error) {
    console.error('Monitor error:', error instanceof Error ? error.message : String(error))
  }
}

function startMonitoring(): void {
  if (monitorInterval) {
    return
  }

  console.log('🎵 Starting Apple Music monitoring...')

  // Initial check
  monitor()

  // Start monitoring
  monitorInterval = setInterval(monitor, POLL_INTERVAL)
}

// Startup
console.log('🎵 Apple Music Monitor starting...')
console.log(`Server URL: ${SERVER_URL}`)
console.log(`Poll interval: ${POLL_INTERVAL}ms`)

// Connect to WebSocket
connectWebSocket()

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down Apple Music Monitor...')

  if (monitorInterval) {
    clearInterval(monitorInterval)
  }

  if (reconnectTimer) {
    clearTimeout(reconnectTimer)
  }

  if (ws) {
    ws.close()
  }

  process.exit(0)
})

process.on('SIGTERM', () => {
  console.log('\n🛑 Shutting down Apple Music Monitor...')

  if (monitorInterval) {
    clearInterval(monitorInterval)
  }

  if (reconnectTimer) {
    clearTimeout(reconnectTimer)
  }

  if (ws) {
    ws.close()
  }

  process.exit(0)
})

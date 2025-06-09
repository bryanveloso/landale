#!/usr/bin/env bun
import { $ } from 'bun'

const EMOTES_DIR = new URL('../apps/overlays/public/emotes/', import.meta.url).pathname
const MANIFEST_PATH = `${EMOTES_DIR}manifest.json`

interface EmoteManifest {
  lastUpdated: string
  emotes: Record<
    string,
    {
      id: string
      name: string
      formats: string[]
      cachedAt: string
    }
  >
}

// Twitch CDN URL patterns
const TWITCH_CDN = 'https://static-cdn.jtvnw.net/emoticons/v2'
const SIZES = ['1.0', '2.0', '3.0'] // 28px, 56px, 112px

async function ensureDirectory() {
  await $`mkdir -p ${EMOTES_DIR}`
}

async function loadManifest(): Promise<EmoteManifest> {
  const file = Bun.file(MANIFEST_PATH)
  if (await file.exists()) {
    return await file.json()
  }
  return { lastUpdated: new Date().toISOString(), emotes: {} }
}

async function downloadEmote(emoteId: string, emoteName: string) {
  console.log(`Downloading emote: ${emoteName} (${emoteId})`)

  const downloads = SIZES.map(async (size) => {
    const url = `${TWITCH_CDN}/${emoteId}/default/dark/${size}`
    const filename = `${emoteId}_${size.replace('.', '')}.png`
    const filepath = `${EMOTES_DIR}${filename}`

    try {
      const response = await fetch(url)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      await Bun.write(filepath, response)
      console.log(`  ✓ Downloaded ${size}`)
    } catch (error) {
      console.error(`  ✗ Failed to download ${size}:`, error)
    }
  })

  await Promise.all(downloads)
}

async function cacheChannelEmotes() {
  const { TWITCH_USER_ID, TWITCH_CLIENT_ID } = Bun.env

  if (!TWITCH_USER_ID || !TWITCH_CLIENT_ID) {
    console.error('Missing required environment variables:')
    console.error('- TWITCH_USER_ID')
    console.error('- TWITCH_CLIENT_ID')
    process.exit(1)
  }

  // Read the access token from the server's token file
  const tokenPath = new URL('../packages/server/src/events/twitch/twitch-token.json', import.meta.url).pathname
  const tokenFile = Bun.file(tokenPath)

  if (!(await tokenFile.exists())) {
    console.error('Token file not found at:', tokenPath)
    console.error('Make sure the server has been run at least once to generate the token.')
    process.exit(1)
  }

  const tokenData = await tokenFile.json()
  const accessToken = tokenData.accessToken

  if (!accessToken) {
    console.error('No access token found in token file')
    process.exit(1)
  }

  await ensureDirectory()
  const manifest = await loadManifest()

  // Fetch only channel emotes from Twitch API
  const response = await fetch(`https://api.twitch.tv/helix/chat/emotes?broadcaster_id=${TWITCH_USER_ID}`, {
    headers: {
      'Client-ID': TWITCH_CLIENT_ID,
      Authorization: `Bearer ${accessToken}`
    }
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch emotes: ${response.status}`)
  }

  const data = await response.json()
  console.log(`Found ${data.data.length} channel emotes`)

  // Download all emotes in parallel
  await Promise.all(
    data.data.map(async (emote: any) => {
      await downloadEmote(emote.id, emote.name)
      manifest.emotes[emote.id] = {
        id: emote.id,
        name: emote.name,
        formats: emote.format,
        cachedAt: new Date().toISOString()
      }
    })
  )

  manifest.lastUpdated = new Date().toISOString()
  await Bun.write(MANIFEST_PATH, JSON.stringify(manifest, null, 2))
  console.log(`\nSuccessfully cached ${Object.keys(manifest.emotes).length} emotes`)
}

// Run the script
await cacheChannelEmotes()

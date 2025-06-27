#!/usr/bin/env bun
import { readFileSync } from 'fs'
import { argv } from 'process'

// Simple log analyzer to identify noisy log patterns
interface LogStats {
  total: number
  byLevel: Record<string, number>
  byMessage: Record<string, number>
  byHour: Record<string, number>
  noisyPatterns: Array<{ pattern: string; count: number }>
}

function analyzeLogs(filePath: string): LogStats {
  const content = readFileSync(filePath, 'utf-8')
  const lines = content.split('\n').filter((line) => line.trim())

  const stats: LogStats = {
    total: 0,
    byLevel: {},
    byMessage: {},
    byHour: {},
    noisyPatterns: []
  }

  // Pattern groups for common noisy logs
  const patterns = [
    { regex: /Buffer: \d+\.\d+s of audio/, name: 'Audio buffer status' },
    { regex: /Processing \d+\.\d+s of audio/, name: 'Audio processing' },
    { regex: /Transcription completed in \d+ms/, name: 'Transcription timing' },
    { regex: /Spawning whisper:/, name: 'Whisper spawning' },
    { regex: /Starting new audio buffer/, name: 'Buffer initialization' },
    { regex: /Audio packet:/, name: 'Audio packet details' },
    { regex: /Header: timestamp=/, name: 'Audio header logging' }
  ]

  const patternCounts: Record<string, number> = {}

  for (const line of lines) {
    stats.total++

    try {
      // Parse JSON log
      const log = JSON.parse(line)

      // Count by level
      const level =
        log.level === 30
          ? 'info'
          : log.level === 20
            ? 'debug'
            : log.level === 40
              ? 'warn'
              : log.level === 50
                ? 'error'
                : 'unknown'
      stats.byLevel[level] = (stats.byLevel[level] || 0) + 1

      // Count by hour
      const hour = new Date(log.time).getHours()
      stats.byHour[hour] = (stats.byHour[hour] || 0) + 1

      // Count by message
      const msg = log.msg
      if (msg) {
        // Check against patterns
        let matched = false
        for (const pattern of patterns) {
          if (pattern.regex.test(msg)) {
            patternCounts[pattern.name] = (patternCounts[pattern.name] || 0) + 1
            matched = true
            break
          }
        }

        if (!matched) {
          // Count exact messages for non-pattern logs
          const shortMsg = msg.substring(0, 50)
          stats.byMessage[shortMsg] = (stats.byMessage[shortMsg] || 0) + 1
        }
      }
    } catch {
      // Skip non-JSON lines
    }
  }

  // Find noisy patterns
  stats.noisyPatterns = Object.entries(patternCounts)
    .map(([pattern, count]) => ({ pattern, count }))
    .sort((a, b) => b.count - a.count)

  return stats
}

function formatStats(stats: LogStats): void {
  console.log('\\n📊 Log Analysis Report\\n')
  console.log(`Total log entries: ${stats.total.toLocaleString()}`)

  console.log('\\n📈 Log Levels:')
  for (const [level, count] of Object.entries(stats.byLevel)) {
    const percent = ((count / stats.total) * 100).toFixed(1)
    console.log(`  ${level.padEnd(10)} ${count.toString().padStart(8)} (${percent}%)`)
  }

  console.log('\\n🔊 Noisy Patterns:')
  for (const { pattern, count } of stats.noisyPatterns.slice(0, 10)) {
    const percent = ((count / stats.total) * 100).toFixed(1)
    console.log(`  ${pattern.padEnd(30)} ${count.toString().padStart(8)} (${percent}%)`)
  }

  console.log('\\n📝 Most Common Messages:')
  const topMessages = Object.entries(stats.byMessage)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 10)

  for (const [msg, count] of topMessages) {
    const percent = ((count / stats.total) * 100).toFixed(1)
    console.log(`  ${msg.padEnd(50)} ${count.toString().padStart(8)} (${percent}%)`)
  }

  console.log('\\n⏰ Activity by Hour:')
  for (let hour = 0; hour < 24; hour++) {
    const count = stats.byHour[hour] || 0
    if (count > 0) {
      const bar = '█'.repeat(Math.ceil((count / stats.total) * 100))
      console.log(`  ${hour.toString().padStart(2, '0')}:00  ${bar} ${count}`)
    }
  }

  console.log('\\n💡 Recommendations:')

  // Check if debug logs are in production
  if (stats.byLevel.debug && stats.byLevel.debug > stats.total * 0.1) {
    console.log('  ⚠️  Debug logs make up >10% of total - consider raising log level')
  }

  // Check for noisy patterns
  for (const { pattern, count } of stats.noisyPatterns) {
    if (count > stats.total * 0.05) {
      console.log(
        `  ⚠️  "${pattern}" represents ${((count / stats.total) * 100).toFixed(1)}% of logs - consider DEBUG level`
      )
    }
  }

  // Estimate daily log size
  const avgLineSize = 200 // bytes
  const dailySize = (stats.total * avgLineSize) / 1024 / 1024
  console.log(`\\n  📦 Estimated log size: ${dailySize.toFixed(1)}MB per time period`)

  if (dailySize > 100) {
    console.log('  ⚠️  High log volume detected - implement log rotation!')
  }
}

// Main
const logFile = argv[2]
if (!logFile) {
  console.error('Usage: bun run analyze-logs.ts <log-file>')
  process.exit(1)
}

try {
  const stats = analyzeLogs(logFile)
  formatStats(stats)
} catch (error) {
  console.error('Error analyzing logs:', error)
  process.exit(1)
}

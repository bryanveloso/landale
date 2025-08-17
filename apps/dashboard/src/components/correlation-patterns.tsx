/**
 * Correlation Patterns Component
 *
 * Displays pattern distribution and hot phrases from the correlation engine.
 * Shows which types of correlations are most common and trending phrases.
 */

import { Show, For, createSignal, onMount } from 'solid-js'
import { useCorrelationChannel } from '@/hooks/use-correlation-channel'

export function CorrelationPatterns() {
  const { patternDistribution, correlations, isConnected, requestPatternDistribution } = useCorrelationChannel()

  const [hotPhrases, setHotPhrases] = createSignal<Array<{ phrase: string; count: number }>>([])

  // Calculate hot phrases from recent correlations
  const calculateHotPhrases = () => {
    const phraseMap = new Map<string, number>()

    correlations.forEach((correlation) => {
      // Extract keywords and common phrases
      correlation.detected_keywords.forEach((keyword) => {
        const normalized = keyword.toLowerCase()
        phraseMap.set(normalized, (phraseMap.get(normalized) || 0) + 1)
      })

      // Also analyze chat text for common words (simplified)
      const words = correlation.chat_text
        .toLowerCase()
        .split(/\s+/)
        .filter((word) => word.length > 3 && !isCommonWord(word))

      words.forEach((word) => {
        phraseMap.set(word, (phraseMap.get(word) || 0) + 1)
      })
    })

    // Convert to sorted array
    const sorted = Array.from(phraseMap.entries())
      .map(([phrase, count]) => ({ phrase, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10)

    setHotPhrases(sorted)
  }

  // Update hot phrases when correlations change
  onMount(() => {
    const interval = setInterval(() => {
      if (isConnected) {
        requestPatternDistribution()
        calculateHotPhrases()
      }
    }, 30000)

    // Initial calculation
    calculateHotPhrases()

    return () => clearInterval(interval)
  })

  // Simple common word filter
  const isCommonWord = (word: string) => {
    const commonWords = new Set([
      'the',
      'and',
      'that',
      'have',
      'for',
      'not',
      'with',
      'you',
      'this',
      'but',
      'his',
      'from',
      'they',
      'she',
      'her',
      'been',
      'than',
      'its',
      'who',
      'oil',
      'now',
      'how',
      'what',
      'when',
      'where',
      'why',
      'yes',
      'can',
      'will',
      'get'
    ])
    return commonWords.has(word) || /^\d+$/.test(word)
  }

  const getPatternColor = (pattern: string) => {
    switch (pattern) {
      case 'direct_quote':
        return 'bg-green-500'
      case 'keyword_echo':
        return 'bg-blue-500'
      case 'emote_reaction':
        return 'bg-yellow-500'
      case 'question_response':
        return 'bg-purple-500'
      case 'temporal_only':
        return 'bg-gray-500'
      default:
        return 'bg-gray-400'
    }
  }

  const formatPatternName = (pattern: string) => {
    return pattern.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase())
  }

  const getTotalPatterns = () => {
    return Object.values(patternDistribution).reduce((sum, count) => sum + count, 0)
  }

  const getPatternPercentage = (count: number) => {
    const total = getTotalPatterns()
    return total > 0 ? Math.round((count / total) * 100) : 0
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <h3 class="mb-2 text-xs font-medium text-gray-300">Pattern Analysis</h3>

      <Show
        when={isConnected && (Object.keys(patternDistribution).length > 0 || hotPhrases().length > 0)}
        fallback={
          <div class="text-xs text-gray-500">
            <Show when={!isConnected} fallback={<span>Analyzing patterns...</span>}>
              <span class="text-red-400">Disconnected from pattern analysis</span>
            </Show>
          </div>
        }>
        {/* Pattern Distribution */}
        <Show when={Object.keys(patternDistribution).length > 0}>
          <div class="mb-4">
            <div class="mb-2 text-xs font-medium text-gray-400">Pattern Distribution</div>
            <div class="space-y-1">
              <For each={Object.entries(patternDistribution).sort(([, a], [, b]) => b - a)}>
                {([pattern, count]) => {
                  const percentage = getPatternPercentage(count)
                  return (
                    <div class="flex items-center justify-between text-xs">
                      <div class="flex items-center gap-2">
                        <div class={`h-2 w-2 rounded-full ${getPatternColor(pattern)}`} />
                        <span class="text-gray-300">{formatPatternName(pattern)}</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="h-1 w-12 rounded-full bg-gray-700">
                          <div
                            class={`h-full rounded-full ${getPatternColor(pattern)}`}
                            style={{ width: `${percentage}%` }}
                          />
                        </div>
                        <span class="w-8 text-right font-mono text-gray-400">{count}</span>
                        <span class="w-8 text-right font-mono text-gray-500">{percentage}%</span>
                      </div>
                    </div>
                  )
                }}
              </For>
            </div>
            <div class="mt-2 text-xs text-gray-500">Total patterns: {getTotalPatterns()}</div>
          </div>
        </Show>

        {/* Hot Phrases */}
        <Show when={hotPhrases().length > 0}>
          <div>
            <div class="mb-2 text-xs font-medium text-gray-400">Hot Phrases</div>
            <div class="space-y-1">
              <For each={hotPhrases().slice(0, 8)}>
                {(phrase, index) => {
                  const maxCount = hotPhrases()[0]?.count || 1
                  const intensity = phrase.count / maxCount
                  const opacityClass = intensity > 0.7 ? 'opacity-100' : intensity > 0.4 ? 'opacity-75' : 'opacity-50'

                  return (
                    <div class="flex items-center justify-between text-xs">
                      <div class="flex items-center gap-2">
                        <span class={`text-xs ${index() < 3 ? 'text-yellow-400' : 'text-gray-400'}`}>
                          #{index() + 1}
                        </span>
                        <span class={`rounded bg-blue-600 px-1 py-0.5 text-white ${opacityClass}`}>
                          {phrase.phrase}
                        </span>
                      </div>
                      <span class="font-mono text-gray-400">{phrase.count}</span>
                    </div>
                  )
                }}
              </For>
            </div>

            <Show when={hotPhrases().length > 8}>
              <div class="mt-2 text-xs text-gray-500">+{hotPhrases().length - 8} more phrases</div>
            </Show>
          </div>
        </Show>

        {/* Pattern Insights */}
        <Show when={Object.keys(patternDistribution).length > 0}>
          <div class="mt-4 border-t border-gray-700 pt-3">
            <div class="mb-1 text-xs font-medium text-gray-400">Insights</div>
            <div class="space-y-1 text-xs text-gray-500">
              <Show when={patternDistribution.direct_quote > getTotalPatterns() * 0.3}>
                <div class="flex items-center gap-1 text-green-400">
                  <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  High quote correlation - viewers responding to specific phrases
                </div>
              </Show>

              <Show when={patternDistribution.emote_reaction > getTotalPatterns() * 0.25}>
                <div class="flex items-center gap-1 text-yellow-400">
                  <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Strong emotional reactions - engaging content
                </div>
              </Show>

              <Show when={patternDistribution.question_response > getTotalPatterns() * 0.2}>
                <div class="flex items-center gap-1 text-purple-400">
                  <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Active Q&A - good viewer engagement
                </div>
              </Show>

              <Show when={getTotalPatterns() === 0}>
                <div class="text-gray-500">Waiting for correlation patterns to emerge...</div>
              </Show>
            </div>
          </div>
        </Show>
      </Show>
    </div>
  )
}

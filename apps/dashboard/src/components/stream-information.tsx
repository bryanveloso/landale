/**
 * Stream Information Component
 *
 * Comprehensive stream management interface similar to Twitch's "Edit Stream Info".
 * Allows updating stream title, game category, language, and other channel properties.
 * Changes trigger EventSub events that automatically update show context.
 */

import { createSignal, createResource, For, Show, onMount, createEffect, onCleanup, untrack } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import type { ChannelInfoUpdate } from '@/services/stream-service'
import { useLayerState } from '@/hooks/use-layer-state'
import { Button } from './ui/button'
import { StreamValidationRules, validateForm, sanitizeFormData } from '@/services/form-validation'
import type { ValidationRule } from '@/services/form-validation'
import { createLogger } from '@landale/logger'

const logger = createLogger({
  service: 'dashboard',
  defaultMeta: { module: 'StreamInformation' }
})

interface ChannelInfo {
  broadcaster_id: string
  broadcaster_login: string
  broadcaster_name: string
  broadcaster_language: string
  game_id: string
  game_name: string
  title: string
  delay: number
  tags: string[]
  branded_content: boolean
}

interface GameCategory {
  id: string
  name: string
  box_art_url: string
  igdb_id: string
}

export function StreamInformation() {
  const { connectionState, getChannelInfo, searchCategories, updateChannelInfo } = useStreamService()
  const { layerState } = useLayerState()

  const [isExpanded, setIsExpanded] = createSignal(false)
  const [isEditing, setIsEditing] = createSignal(false)
  const [isSubmitting, setIsSubmitting] = createSignal(false)
  const [lastAction, setLastAction] = createSignal<string | null>(null)

  // Form state
  const [title, setTitle] = createSignal('')
  const [gameId, setGameId] = createSignal('')
  const [gameName, setGameName] = createSignal('')
  const [language, setLanguage] = createSignal('')
  const [categorySearch, setCategorySearch] = createSignal('')
  const [searchResults, setSearchResults] = createSignal<GameCategory[]>([])
  const [showSearch, setShowSearch] = createSignal(false)
  const [searchTimeout, setSearchTimeout] = createSignal<ReturnType<typeof setTimeout> | null>(null)

  const isConnected = () => connectionState().connected
  const currentShow = () => layerState().current_show

  // Load current channel information
  const [channelInfo, { refetch: refetchChannelInfo }] = createResource(
    () => isConnected() && isExpanded(),
    async () => {
      if (!isConnected()) return null

      try {
        const response = await getChannelInfo()
        if (response.status === 'ok' && response.data) {
          // The backend returns the channel info in the data property
          return response.data as unknown as ChannelInfo
        }
        return null
      } catch (error) {
        logger.error('Failed to load channel info', { error: error instanceof Error ? { message: error.message, type: error.constructor.name } : { message: String(error) } })
        setLastAction('Failed to load channel information')
        return null
      }
    }
  )

  // Update form when channel info loads
  const updateFormFromChannelInfo = (info: ChannelInfo) => {
    setTitle(info.title || '')
    setGameId(info.game_id || '')
    setGameName(info.game_name || '')
    setLanguage(info.broadcaster_language || 'en')
  }

  // Initialize form when channel info loads
  onMount(() => {
    const info = channelInfo()
    if (info) {
      updateFormFromChannelInfo(info)
    }
  })

  // Debounced search effect
  createEffect(() => {
    const query = categorySearch()

    // Clear existing timeout (use untrack to avoid reactivity loop)
    untrack(() => {
      const existingTimeout = searchTimeout()
      if (existingTimeout) {
        clearTimeout(existingTimeout)
      }
    })

    // Set new timeout for debouncing
    const timeoutId = setTimeout(() => {
      handleSearchCategories(query)
    }, 300) // 300ms debounce delay

    setSearchTimeout(timeoutId)
  })

  // Cleanup timeout on unmount
  onCleanup(() => {
    const timeoutId = searchTimeout()
    if (timeoutId) {
      clearTimeout(timeoutId)
    }
  })

  const handleSearchCategories = async (query: string) => {
    if (!isConnected() || query.trim().length < 2) {
      setSearchResults([])
      return
    }

    try {
      const response = await searchCategories(query)
      if (response.status === 'ok' && response.data) {
        // The backend returns an array of categories
        const categories = response.data as unknown as GameCategory[]
        setSearchResults(categories)
      } else {
        setSearchResults([])
      }
    } catch (error) {
      logger.error('Failed to search categories', { error: error instanceof Error ? { message: error.message, type: error.constructor.name } : { message: String(error) }, metadata: { query } })
      setSearchResults([])
    }
  }

  const handleSelectCategory = (category: GameCategory) => {
    setGameId(category.id)
    setGameName(category.name)
    setShowSearch(false)
    setCategorySearch('')
    setSearchResults([])
  }

  const handleSubmit = async () => {
    if (!isConnected() || isSubmitting()) return

    setIsSubmitting(true)
    setLastAction('Updating channel information...')

    // Validate form data
    const formData = sanitizeFormData({
      title: title(),
      game_id: gameId(),
      broadcaster_language: language()
    })

    const validation = validateForm(formData, {
      title: StreamValidationRules.streamTitle as ValidationRule<unknown>[],
      game_id: StreamValidationRules.gameCategory as ValidationRule<unknown>[],
      broadcaster_language: StreamValidationRules.language as ValidationRule<unknown>[]
    })

    if (!validation.isValid) {
      setLastAction(`Validation failed: ${validation.errors.join(', ')}`)
      setIsSubmitting(false)
      return
    }

    const updates: ChannelInfoUpdate = {}

    const currentInfo = channelInfo()
    if (currentInfo) {
      if (formData.title !== currentInfo.title) updates.title = formData.title
      if (formData.game_id !== currentInfo.game_id) updates.game_id = formData.game_id
      if (formData.broadcaster_language !== currentInfo.broadcaster_language)
        updates.broadcaster_language = formData.broadcaster_language
    }

    if (Object.keys(updates).length === 0) {
      setLastAction('No changes to save')
      setIsSubmitting(false)
      setIsEditing(false)
      return
    }

    try {
      const response = await updateChannelInfo(updates)
      if (response.status === 'ok') {
        setLastAction('Channel information updated successfully')
        setIsEditing(false)
        // Refresh channel info to show updated values
        refetchChannelInfo()
      } else {
        throw new Error('Update failed')
      }
    } catch (error) {
      logger.error('Failed to update channel info', { error: error instanceof Error ? { message: error.message, type: error.constructor.name } : { message: String(error) }, metadata: { updates } })
      setLastAction('Failed to update channel information')
    }

    setIsSubmitting(false)

    // Clear success message after 3 seconds
    setTimeout(() => {
      if (lastAction()?.includes('successfully')) {
        setLastAction(null)
      }
    }, 3000)
  }

  const handleCancel = () => {
    const info = channelInfo()
    if (info) {
      updateFormFromChannelInfo(info)
    }
    setIsEditing(false)
    setShowSearch(false)
    setCategorySearch('')
    setSearchResults([])
  }

  const commonGameCategories: GameCategory[] = [
    { id: '509660', name: 'Just Chatting', box_art_url: '', igdb_id: '' },
    { id: '509658', name: 'Software and Game Development', box_art_url: '', igdb_id: '' },
    { id: '490100', name: 'Pokémon FireRed/LeafGreen', box_art_url: '', igdb_id: '' },
    { id: '518203', name: 'Slots', box_art_url: '', igdb_id: '' },
    { id: '509659', name: 'Art', box_art_url: '', igdb_id: '' },
    { id: '509663', name: 'Special Events', box_art_url: '', igdb_id: '' }
  ]

  return (
    <section class="stream-information">
      <header class="info-header">
        <Button onClick={() => setIsExpanded(!isExpanded())} variant="outline" size="sm" disabled={!isConnected()}>
          📺 Stream Info {isExpanded() ? '▼' : '▶'}
        </Button>
        <div class="current-show">Show: {currentShow()}</div>
      </header>

      <Show when={isExpanded()}>
        <main class="info-content">
          <Show when={channelInfo.loading}>
            <div class="loading">Loading channel information...</div>
          </Show>

          <Show when={channelInfo() && !channelInfo.loading}>
            <div class="channel-info">
              {!isEditing() ? (
                // Display mode
                <div class="info-display">
                  <div class="info-field">
                    <label>Title:</label>
                    <span class="field-value">{channelInfo()?.title || 'No title set'}</span>
                  </div>
                  <div class="info-field">
                    <label>Game:</label>
                    <span class="field-value">{channelInfo()?.game_name || 'No game set'}</span>
                  </div>
                  <div class="info-field">
                    <label>Language:</label>
                    <span class="field-value">{channelInfo()?.broadcaster_language || 'en'}</span>
                  </div>
                  <div class="info-actions">
                    <Button onClick={() => setIsEditing(true)} disabled={!isConnected() || isSubmitting()} size="sm">
                      Edit
                    </Button>
                    <Button
                      onClick={() => refetchChannelInfo()}
                      disabled={!isConnected() || isSubmitting()}
                      variant="outline"
                      size="sm">
                      Refresh
                    </Button>
                  </div>
                </div>
              ) : (
                // Edit mode
                <form class="info-edit">
                  <div class="form-field">
                    <label>Stream Title:</label>
                    <input
                      type="text"
                      value={title()}
                      onInput={(e) => setTitle(e.target.value)}
                      placeholder="Enter stream title..."
                      disabled={isSubmitting()}
                      maxlength="140"
                    />
                  </div>

                  <div class="form-field">
                    <label>Game Category:</label>
                    <div class="game-selector">
                      <input
                        type="text"
                        value={showSearch() ? categorySearch() : gameName()}
                        onInput={(e) => {
                          setCategorySearch(e.target.value)
                        }}
                        onFocus={() => setShowSearch(true)}
                        placeholder="Search for game..."
                        disabled={isSubmitting()}
                      />
                      <Button
                        onClick={() => setShowSearch(!showSearch())}
                        variant="outline"
                        size="sm"
                        disabled={isSubmitting()}>
                        {showSearch() ? '✕' : '🔍'}
                      </Button>
                    </div>

                    <Show when={showSearch()}>
                      <div class="category-search">
                        <div class="quick-categories">
                          <label>Common Categories:</label>
                          <div class="category-buttons">
                            <For each={commonGameCategories}>
                              {(category) => (
                                <Button
                                  onClick={() => handleSelectCategory(category)}
                                  variant="outline"
                                  size="sm"
                                  disabled={isSubmitting()}>
                                  {category.name}
                                </Button>
                              )}
                            </For>
                          </div>
                        </div>

                        <Show when={searchResults().length > 0}>
                          <div class="search-results">
                            <label>Search Results:</label>
                            <div class="results-list">
                              <For each={searchResults()}>
                                {(category) => (
                                  <div class="result-item" onClick={() => handleSelectCategory(category)}>
                                    <span class="category-name">{category.name}</span>
                                    <span class="category-id">ID: {category.id}</span>
                                  </div>
                                )}
                              </For>
                            </div>
                          </div>
                        </Show>
                      </div>
                    </Show>
                  </div>

                  <div class="form-field">
                    <label>Language:</label>
                    <select value={language()} onInput={(e) => setLanguage(e.target.value)} disabled={isSubmitting()}>
                      <option value="en">English</option>
                      <option value="es">Spanish</option>
                      <option value="fr">French</option>
                      <option value="de">German</option>
                      <option value="it">Italian</option>
                      <option value="pt">Portuguese</option>
                      <option value="ru">Russian</option>
                      <option value="ja">Japanese</option>
                      <option value="ko">Korean</option>
                      <option value="zh">Chinese</option>
                    </select>
                  </div>

                  <div class="form-actions">
                    <Button onClick={handleSubmit} disabled={isSubmitting() || !isConnected()} size="sm">
                      {isSubmitting() ? 'Saving...' : 'Save Changes'}
                    </Button>
                    <Button onClick={handleCancel} variant="outline" size="sm" disabled={isSubmitting()}>
                      Cancel
                    </Button>
                  </div>
                </form>
              )}
            </div>
          </Show>

          <Show when={lastAction()}>
            <div class="action-status">
              <div class="status-message">{lastAction()}</div>
            </div>
          </Show>

          <Show when={!isConnected()}>
            <div class="disconnected-warning">
              <span>⚠️ Not connected to server</span>
            </div>
          </Show>
        </main>
      </Show>
    </section>
  )
}

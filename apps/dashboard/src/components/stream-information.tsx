/**
 * Stream Information Component
 *
 * Comprehensive stream management interface similar to Twitch's "Edit Stream Info".
 * Allows updating stream title, game category, language, and other channel properties.
 * Changes trigger EventSub events that automatically update show context.
 */

import { createSignal, createResource, For, Show, onMount, createEffect, onCleanup, untrack } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import { useStreamCommands } from '@/hooks/use-stream-commands'
import { useLayerState } from '@/hooks/use-layer-state'
import { Button } from './ui/button'
import { createLogger } from '@landale/logger/browser'
import { handleError, handleAsyncOperation } from '@/services/error-handler'
import { StreamValidationRules, validateForm, sanitizeFormData } from '@/services/form-validation'

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

const logger = createLogger({
  service: 'dashboard',
  level: 'info',
  enableConsole: true
})

export function StreamInformation() {
  const { connectionState } = useStreamService()
  const { sendCommand } = useStreamCommands()
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
  const [searchTimeout, setSearchTimeout] = createSignal<number | null>(null)

  const isConnected = () => connectionState().connected
  const currentShow = () => layerState().current_show

  // Load current channel information
  const [channelInfo, { refetch: refetchChannelInfo }] = createResource(
    () => isConnected() && isExpanded(),
    async () => {
      if (!isConnected()) return null

      const result = await handleAsyncOperation(() => sendCommand('get_channel_info', {}), {
        component: 'StreamInformation',
        operation: 'load channel information',
        data: {}
      })

      if (result.success && result.data.status === 'ok') {
        return result.data.data.data?.[0] as ChannelInfo // Twitch API returns array
      }
      return null
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

    const result = await handleAsyncOperation(() => sendCommand('search_categories', { query: query.trim() }), {
      component: 'StreamInformation',
      operation: 'search game categories',
      data: { query }
    })

    if (result.success && result.data.status === 'ok') {
      setSearchResults(result.data.data.data || [])
    } else {
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
      title: StreamValidationRules.streamTitle,
      game_id: StreamValidationRules.gameCategory,
      broadcaster_language: StreamValidationRules.language
    })

    if (!validation.isValid) {
      setLastAction(`Validation failed: ${validation.errors.join(', ')}`)
      setIsSubmitting(false)
      return
    }

    const updates: any = {}

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

    const result = await handleAsyncOperation(() => sendCommand('update_channel_info', updates), {
      component: 'StreamInformation',
      operation: 'update channel information',
      data: updates
    })

    if (result.success && result.data.status === 'ok') {
      setLastAction('Channel information updated successfully')
      setIsEditing(false)
      // Refresh channel info after update
      setTimeout(() => refetchChannelInfo(), 1000)
    } else {
      const errorMessage = result.success ? `Failed to update: ${result.data.error}` : result.error.userMessage
      setLastAction(errorMessage)
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

  const commonGameCategories = [
    { id: '509660', name: 'Just Chatting' },
    { id: '509658', name: 'Software and Game Development' },
    { id: '490100', name: 'Pokémon FireRed/LeafGreen' },
    { id: '518203', name: 'Slots' },
    { id: '509659', name: 'Art' },
    { id: '509663', name: 'Special Events' }
  ]

  return (
    <section data-stream-information>
      <header data-info-header>
        <Button onClick={() => setIsExpanded(!isExpanded())} variant="outline" size="sm" disabled={!isConnected()}>
          📺 Stream Info {isExpanded() ? '▼' : '▶'}
        </Button>
        <div data-current-show>Show: {currentShow()}</div>
      </header>

      <Show when={isExpanded()}>
        <main data-info-content>
          <Show when={channelInfo.loading}>
            <div data-loading>Loading channel information...</div>
          </Show>

          <Show when={channelInfo() && !channelInfo.loading}>
            <div data-channel-info>
              {!isEditing() ? (
                // Display mode
                <div data-info-display>
                  <div data-info-field>
                    <label>Title:</label>
                    <span data-field-value>{channelInfo()?.title || 'No title set'}</span>
                  </div>
                  <div data-info-field>
                    <label>Game:</label>
                    <span data-field-value>{channelInfo()?.game_name || 'No game set'}</span>
                  </div>
                  <div data-info-field>
                    <label>Language:</label>
                    <span data-field-value>{channelInfo()?.broadcaster_language || 'en'}</span>
                  </div>
                  <div data-info-actions>
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
                <form data-info-edit>
                  <div data-form-field>
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

                  <div data-form-field>
                    <label>Game Category:</label>
                    <div data-game-selector>
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

                  <div data-form-field>
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

                  <div data-form-actions>
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
            <div data-action-status>
              <div data-status-message>{lastAction()}</div>
            </div>
          </Show>

          <Show when={!isConnected()}>
            <div data-disconnected-warning>
              <span>⚠️ Not connected to server</span>
            </div>
          </Show>
        </main>
      </Show>
    </section>
  )
}

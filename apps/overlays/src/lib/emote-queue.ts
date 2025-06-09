type EmoteListener = (emoteId: string) => void

class EmoteQueue {
  private static instance: EmoteQueue | undefined
  private listeners: Set<EmoteListener> = new Set()

  private constructor() {}

  static getInstance(): EmoteQueue {
    if (!EmoteQueue.instance) {
      EmoteQueue.instance = new EmoteQueue()
    }
    return EmoteQueue.instance
  }

  on(_event: 'emote', listener: EmoteListener) {
    this.listeners.add(listener)
  }

  off(_event: 'emote', listener: EmoteListener) {
    this.listeners.delete(listener)
  }

  queueEmote(emoteId: string) {
    this.listeners.forEach((listener) => {
      listener(emoteId)
    })
  }
}

export const emoteQueue = EmoteQueue.getInstance()

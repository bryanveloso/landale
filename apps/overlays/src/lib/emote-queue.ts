import { EventEmitter } from 'events'

class EmoteQueue extends EventEmitter {
  private static instance: EmoteQueue

  private constructor() {
    super()
  }

  static getInstance(): EmoteQueue {
    if (!EmoteQueue.instance) {
      EmoteQueue.instance = new EmoteQueue()
    }
    return EmoteQueue.instance
  }

  queueEmote(emoteId: string) {
    this.emit('emote', emoteId)
  }
}

export const emoteQueue = EmoteQueue.getInstance()
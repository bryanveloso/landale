declare global {
  interface Window {
    queueEmote?: (emoteId: string) => void
  }
}

export {}

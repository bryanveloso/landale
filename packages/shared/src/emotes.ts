/**
 * Avalonstar Channel Emote Repository
 *
 * Contains the actual 102 channel-specific emotes from avalonstar's Twitch channel
 * with their real meanings and contexts for AI-driven emote selection.
 *
 * Shared across dashboard, overlays, and phononmaser for consistent emote handling.
 */

export interface EmoteAnalysis {
  emotion: 'excited' | 'frustrated' | 'confused' | 'happy' | 'sad' | 'neutral' | 'hype' | 'thinking'
  intensity: number // 1-10 scale
  triggers: string[] // Suggested emote names
  shouldTrigger: boolean
  confidence: number // 0-1 how confident the AI is
  context: string // Brief explanation
}

export interface EmoteMapping {
  name: string
  category: 'positive' | 'negative' | 'neutral' | 'hype' | 'reaction' | 'action' | 'meme'
  description: string
  keywords: string[]
  intensity: 1 | 2 | 3
}

/**
 * Avalonstar's actual channel emotes with real meanings and contexts
 */
export const AVALONSTAR_EMOTES: Record<string, EmoteMapping> = {
  avalon1HP: {
    name: 'avalon1HP',
    category: 'negative',
    description: 'Low health, dying, critical state',
    keywords: ['low health', 'dying', 'critical', 'almost dead'],
    intensity: 2
  },
  avalon7: {
    name: 'avalon7',
    category: 'action',
    description: 'Salute, military respect',
    keywords: ['salute', 'respect', 'military', 'honor'],
    intensity: 2
  },
  avalonAKTUALLY: {
    name: 'avalonAKTUALLY',
    category: 'reaction',
    description: 'Actually... correction or disagreement',
    keywords: ['actually', 'correction', 'well actually'],
    intensity: 1
  },
  avalonANGY: {
    name: 'avalonANGY',
    category: 'negative',
    description: 'Cute angry, mildly annoyed',
    keywords: ['angry', 'annoyed', 'mad'],
    intensity: 2
  },
  avalonARTSY: {
    name: 'avalonARTSY',
    category: 'action',
    description: 'Art, creative work, design',
    keywords: ['art', 'creative', 'design', 'drawing'],
    intensity: 2
  },
  avalonAYAYA: {
    name: 'avalonAYAYA',
    category: 'hype',
    description: 'Anime excitement, AYAYA',
    keywords: ['anime', 'excited', 'ayaya'],
    intensity: 3
  },
  avalonBELL: {
    name: 'avalonBELL',
    category: 'neutral',
    description: 'Bell sound, notification, ding',
    keywords: ['bell', 'notification', 'ding'],
    intensity: 1
  },
  avalonBLANK: {
    name: 'avalonBLANK',
    category: 'neutral',
    description: 'Blank stare, empty, nothing',
    keywords: ['blank', 'empty', 'nothing', 'void'],
    intensity: 1
  },
  avalonBLESS: {
    name: 'avalonBLESS',
    category: 'positive',
    description: 'Blessed, grateful, thankful',
    keywords: ['blessed', 'grateful', 'thank'],
    intensity: 2
  },
  avalonBLIND: {
    name: 'avalonBLIND',
    category: 'reaction',
    description: 'Cannot see, blind',
    keywords: ['blind', 'cannot see', 'dark'],
    intensity: 1
  },
  avalonBLUSH: {
    name: 'avalonBLUSH',
    category: 'reaction',
    description: 'Embarrassed, shy, blushing',
    keywords: ['embarrassed', 'shy', 'blush'],
    intensity: 2
  },
  avalonBONK: {
    name: 'avalonBONK',
    category: 'reaction',
    description: 'Bonk, hit, smack',
    keywords: ['bonk', 'hit', 'smack'],
    intensity: 2
  },
  avalonBOP: {
    name: 'avalonBOP',
    category: 'action',
    description: 'Star getting hit with a hammer',
    keywords: ['hit', 'hammer', 'bonk', 'strike'],
    intensity: 2
  },
  avalonCHU: {
    name: 'avalonCHU',
    category: 'positive',
    description: 'Kiss sound, cute affection',
    keywords: ['kiss', 'chu', 'affection'],
    intensity: 2
  },
  avalonCLAP: {
    name: 'avalonCLAP',
    category: 'positive',
    description: 'Clapping, applause, well done',
    keywords: ['clap', 'applause', 'good job'],
    intensity: 2
  },
  avalonCOMFY: {
    name: 'avalonCOMFY',
    category: 'action',
    description: 'Comfortable, cozy, relaxed',
    keywords: ['comfy', 'comfortable', 'cozy', 'relaxed'],
    intensity: 1
  },
  avalonCOOL: {
    name: 'avalonCOOL',
    category: 'positive',
    description: 'Cool, awesome, neat',
    keywords: ['cool', 'awesome', 'neat'],
    intensity: 2
  },
  avalonCOZY: {
    name: 'avalonCOZY',
    category: 'action',
    description: 'Cozy, warm, snug',
    keywords: ['cozy', 'warm', 'snug'],
    intensity: 1
  },
  avalonCRY: {
    name: 'avalonCRY',
    category: 'negative',
    description: 'Crying, sad, tears',
    keywords: ['cry', 'sad', 'tears'],
    intensity: 2
  },
  avalonD: {
    name: 'avalonD',
    category: 'negative',
    description: 'Stunned D: face, opposite of :D',
    keywords: ['stunned', 'shocked', 'dismayed'],
    intensity: 2
  },
  avalonDAISHOURI: {
    name: 'avalonDAISHOURI',
    category: 'hype',
    description: 'Great victory, overwhelming victory (Japanese)',
    keywords: ['victory', 'triumph', 'success', 'won'],
    intensity: 3
  },
  avalonDAISHOUWHEE: {
    name: 'avalonDAISHOUWHEE',
    category: 'hype',
    description: 'Great victory + excitement, DAISHOURI but spinning animated',
    keywords: ['victory', 'excited', 'triumph', 'spinning'],
    intensity: 3
  },
  avalonDANCE: {
    name: 'avalonDANCE',
    category: 'hype',
    description: 'Dancing with glowsticks',
    keywords: ['dance', 'groove', 'music', 'glowsticks', 'rave'],
    intensity: 3
  },
  avalonDASH: {
    name: 'avalonDASH',
    category: 'action',
    description: 'Fast movement, rushing, speedy',
    keywords: ['fast', 'speed', 'rush', 'dash'],
    intensity: 2
  },
  avalonDC: {
    name: 'avalonDC',
    category: 'reaction',
    description: 'Disconnect, connection lost',
    keywords: ['disconnect', 'connection lost', 'dc'],
    intensity: 1
  },
  avalonDERP: {
    name: 'avalonDERP',
    category: 'reaction',
    description: 'Derpy, silly, goofy',
    keywords: ['derp', 'silly', 'goofy'],
    intensity: 2
  },
  avalonDOOT: {
    name: 'avalonDOOT',
    category: 'meme',
    description: 'Trumpet doot, skeleton meme',
    keywords: ['doot', 'trumpet', 'skeleton'],
    intensity: 2
  },
  avalonDOZE: {
    name: 'avalonDOZE',
    category: 'action',
    description: 'Dozing, sleepy, tired',
    keywords: ['doze', 'sleep', 'tired', 'sleepy'],
    intensity: 1
  },
  avalonDRIVE: {
    name: 'avalonDRIVE',
    category: 'action',
    description: 'Literally Ava driving',
    keywords: ['drive', 'driving', 'car'],
    intensity: 1
  },
  avalonEUREKA: {
    name: 'avalonEUREKA',
    category: 'positive',
    description: 'Eureka moment, got an idea',
    keywords: ['eureka', 'idea', 'solution', 'figured out'],
    intensity: 3
  },
  avalonEYES: {
    name: 'avalonEYES',
    category: 'positive',
    description: 'Awwwww gaze, admiring something cute',
    keywords: ['aww', 'cute', 'admiring', 'adorable'],
    intensity: 2
  },
  avalonFEELS: {
    name: 'avalonFEELS',
    category: 'reaction',
    description: 'Emotional feels, touching moment',
    keywords: ['feels', 'emotional', 'touching'],
    intensity: 2
  },
  avalonFINE: {
    name: 'avalonFINE',
    category: 'reaction',
    description: 'This is fine meme, everything is fine',
    keywords: ['fine', 'okay', 'this is fine'],
    intensity: 1
  },
  avalonFITE: {
    name: 'avalonFITE',
    category: 'action',
    description: 'Fight, combat, battle',
    keywords: ['fight', 'battle', 'combat'],
    intensity: 2
  },
  avalonFREEZE: {
    name: 'avalonFREEZE',
    category: 'reaction',
    description: 'Animated opposite of fine meme, snow and ice instead of fire',
    keywords: ['freeze', 'cold', 'frozen', 'ice', 'snow'],
    intensity: 2
  },
  avalonGIB: {
    name: 'avalonGIB',
    category: 'reaction',
    description: 'Give me, gib (internet slang)',
    keywords: ['give', 'gib', 'want'],
    intensity: 1
  },
  avalonHAPPY: {
    name: 'avalonHAPPY',
    category: 'positive',
    description: 'Happy, pleased, content',
    keywords: ['happy', 'pleased', 'good'],
    intensity: 2
  },
  avalonHEHE: {
    name: 'avalonHEHE',
    category: 'positive',
    description: 'Giggling, mischievous laugh',
    keywords: ['giggle', 'hehe', 'mischievous'],
    intensity: 2
  },
  avalonHIDE: {
    name: 'avalonHIDE',
    category: 'action',
    description: 'Hiding, sneaking',
    keywords: ['hide', 'sneak', 'hiding'],
    intensity: 1
  },
  avalonHOLY: {
    name: 'avalonHOLY',
    category: 'reaction',
    description: 'Holy, blessed, religious awe',
    keywords: ['holy', 'blessed', 'divine'],
    intensity: 2
  },
  avalonHUG: {
    name: 'avalonHUG',
    category: 'positive',
    description: 'Hugging, warm embrace',
    keywords: ['hug', 'embrace', 'affection'],
    intensity: 2
  },
  avalonHUH: {
    name: 'avalonHUH',
    category: 'neutral',
    description: 'Confused, what?',
    keywords: ['huh', 'what', 'confused'],
    intensity: 1
  },
  avalonHYPE: {
    name: 'avalonHYPE',
    category: 'hype',
    description: 'Hype, excitement, energy',
    keywords: ['hype', 'excited', 'energy', 'lets go'],
    intensity: 3
  },
  avalonINFLUENCED: {
    name: 'avalonINFLUENCED',
    category: 'reaction',
    description: 'Being influenced, convinced',
    keywords: ['influenced', 'convinced', 'persuaded'],
    intensity: 2
  },
  avalonJAM: {
    name: 'avalonJAM',
    category: 'hype',
    description: 'Jamming to music, grooving',
    keywords: ['jam', 'music', 'groove'],
    intensity: 2
  },
  avalonJOY: {
    name: 'avalonJOY',
    category: 'positive',
    description: 'Pure joy, elated',
    keywords: ['joy', 'elated', 'wonderful'],
    intensity: 3
  },
  avalonKANPAI: {
    name: 'avalonKANPAI',
    category: 'positive',
    description: 'Cheers! Japanese toast',
    keywords: ['cheers', 'toast', 'drink', 'kanpai'],
    intensity: 2
  },
  avalonKEK: {
    name: 'avalonKEK',
    category: 'positive',
    description: 'Laughter, kek (like lol)',
    keywords: ['kek', 'lol', 'laugh', 'funny'],
    intensity: 2
  },
  avalonLATE: {
    name: 'avalonLATE',
    category: 'reaction',
    description: 'Ava pointing at watch to signify tardiness',
    keywords: ['late', 'behind', 'tardy', 'watch', 'time'],
    intensity: 2
  },
  avalonLEAVE: {
    name: 'avalonLEAVE',
    category: 'action',
    description: 'Leaving, goodbye, exit',
    keywords: ['leave', 'goodbye', 'exit'],
    intensity: 1
  },
  avalonLOADING: {
    name: 'avalonLOADING',
    category: 'neutral',
    description: 'Loading, waiting, processing',
    keywords: ['loading', 'wait', 'processing'],
    intensity: 1
  },
  avalonLOOT: {
    name: 'avalonLOOT',
    category: 'positive',
    description: 'Getting loot, rewards, treasure',
    keywords: ['loot', 'reward', 'treasure'],
    intensity: 2
  },
  avalonLOVE: {
    name: 'avalonLOVE',
    category: 'positive',
    description: 'Love, heart, affection',
    keywords: ['love', 'heart', 'affection'],
    intensity: 2
  },
  avalonLURK: {
    name: 'avalonLURK',
    category: 'action',
    description: 'Lurking, watching quietly',
    keywords: ['lurk', 'watching', 'quiet'],
    intensity: 1
  },
  avalonMYAAA: {
    name: 'avalonMYAAA',
    category: 'meme',
    description: 'Cat yelling loudly, loud cat noise',
    keywords: ['cat', 'yell', 'loud', 'myaa'],
    intensity: 3
  },
  avalonNOD: {
    name: 'avalonNOD',
    category: 'positive',
    description: 'Nodding in agreement, yes',
    keywords: ['nod', 'agree', 'yes'],
    intensity: 1
  },
  avalonNOM: {
    name: 'avalonNOM',
    category: 'action',
    description: 'Eating, nomming food',
    keywords: ['eat', 'nom', 'food'],
    intensity: 1
  },
  avalonNOPE: {
    name: 'avalonNOPE',
    category: 'negative',
    description: 'Nope, no, refusing',
    keywords: ['nope', 'no', 'refuse'],
    intensity: 1
  },
  avalonNOTE: {
    name: 'avalonNOTE',
    category: 'neutral',
    description: 'Taking notes, important',
    keywords: ['note', 'important', 'remember'],
    intensity: 1
  },
  avalonOHWOAHOHNO: {
    name: 'avalonOHWOAHOHNO',
    category: 'reaction',
    description: 'Animated OWO that quickly switches to avalonBLANK',
    keywords: ['owo', 'surprise', 'shock', 'animated'],
    intensity: 3
  },
  avalonOOF: {
    name: 'avalonOOF',
    category: 'negative',
    description: 'Oof, pain, impact',
    keywords: ['oof', 'pain', 'hurt', 'impact'],
    intensity: 2
  },
  avalonOWO: {
    name: 'avalonOWO',
    category: 'meme',
    description: 'OwO face, cute expression',
    keywords: ['owo', 'cute', 'notices'],
    intensity: 2
  },
  avalonPARTY: {
    name: 'avalonPARTY',
    category: 'hype',
    description: 'Party time, celebration',
    keywords: ['party', 'celebrate', 'fun'],
    intensity: 3
  },
  avalonPAUSE: {
    name: 'avalonPAUSE',
    category: 'reaction',
    description: 'Anticipatory stare, tense stare',
    keywords: ['pause', 'anticipation', 'tense', 'waiting'],
    intensity: 2
  },
  avalonPET: {
    name: 'avalonPET',
    category: 'positive',
    description: 'Petting, gentle affection',
    keywords: ['pet', 'gentle', 'affection'],
    intensity: 1
  },
  avalonPLINK: {
    name: 'avalonPLINK',
    category: 'meme',
    description: 'Cat blinking slowly, plinking cat meme',
    keywords: ['cat', 'blink', 'slow', 'plink'],
    intensity: 1
  },
  avalonPOINT: {
    name: 'avalonPOINT',
    category: 'meme',
    description: 'Woman pointing at cat meme, left side of couple pointing',
    keywords: ['point', 'meme', 'woman', 'cat'],
    intensity: 2
  },
  avalonPOP: {
    name: 'avalonPOP',
    category: 'action',
    description: 'Popping, sudden appearance',
    keywords: ['pop', 'sudden', 'appear'],
    intensity: 2
  },
  avalonRAGE: {
    name: 'avalonRAGE',
    category: 'negative',
    description: 'Rage, furious anger',
    keywords: ['rage', 'angry', 'mad', 'furious'],
    intensity: 3
  },
  avalonREVERSE: {
    name: 'avalonREVERSE',
    category: 'reaction',
    description: 'Ava holding reverse UNO card, reflecting compliments',
    keywords: ['reverse', 'uno', 'reflect', 'compliment'],
    intensity: 2
  },
  avalonRIP: {
    name: 'avalonRIP',
    category: 'negative',
    description: 'Rest in peace, died, failed',
    keywords: ['rip', 'died', 'dead', 'failed'],
    intensity: 2
  },
  avalonS: {
    name: 'avalonS',
    category: 'reaction',
    description: 'Sweating star, S for sweat',
    keywords: ['sweat', 'nervous', 'anxious'],
    intensity: 2
  },
  avalonSHINE: {
    name: 'avalonSHINE',
    category: 'positive',
    description: 'Shining, bright, radiant',
    keywords: ['shine', 'bright', 'radiant'],
    intensity: 2
  },
  avalonSHRUG: {
    name: 'avalonSHRUG',
    category: 'neutral',
    description: "Shrugging, don't know",
    keywords: ['shrug', 'dunno', 'idk'],
    intensity: 1
  },
  avalonSHUCKS: {
    name: 'avalonSHUCKS',
    category: 'positive',
    description: 'Embarrassment and flattery, not disappointment',
    keywords: ['embarrassed', 'flattered', 'aw shucks'],
    intensity: 2
  },
  avalonSIP: {
    name: 'avalonSIP',
    category: 'action',
    description: 'Sipping a drink',
    keywords: ['sip', 'drink', 'tea'],
    intensity: 1
  },
  avalonSIT: {
    name: 'avalonSIT',
    category: 'neutral',
    description: "Sitting down, I'm just sorta here",
    keywords: ['sit', 'here', 'present', 'existing'],
    intensity: 1
  },
  avalonSLIDE: {
    name: 'avalonSLIDE',
    category: 'positive',
    description: 'Ava sliding down chair with hearts',
    keywords: ['slide', 'chair', 'hearts', 'love'],
    intensity: 2
  },
  avalonSMUG: {
    name: 'avalonSMUG',
    category: 'reaction',
    description: 'Smug expression, self-satisfied',
    keywords: ['smug', 'satisfied', 'cocky'],
    intensity: 2
  },
  avalonSPOOK: {
    name: 'avalonSPOOK',
    category: 'reaction',
    description: 'Spooky, scary, spooked',
    keywords: ['spook', 'scary', 'spooked'],
    intensity: 2
  },
  avalonSTAR: {
    name: 'avalonSTAR',
    category: 'neutral',
    description: 'Stream logo, star in an avocado',
    keywords: ['logo', 'star', 'avocado', 'brand'],
    intensity: 1
  },
  avalonSTARE: {
    name: 'avalonSTARE',
    category: 'reaction',
    description: 'Intense staring',
    keywords: ['stare', 'intense', 'watching'],
    intensity: 2
  },
  avalonSTARWHEE: {
    name: 'avalonSTARWHEE',
    category: 'hype',
    description: 'avalonSTAR spinning 360 degrees in place',
    keywords: ['star', 'spinning', 'whee', 'rotate'],
    intensity: 3
  },
  avalonSTONKS: {
    name: 'avalonSTONKS',
    category: 'positive',
    description: 'Stonks meme, profit, success',
    keywords: ['stonks', 'profit', 'success', 'money'],
    intensity: 2
  },
  avalonSTRESS: {
    name: 'avalonSTRESS',
    category: 'negative',
    description: 'Stressed, overwhelmed',
    keywords: ['stress', 'overwhelmed', 'pressure'],
    intensity: 2
  },
  avalonSUS: {
    name: 'avalonSUS',
    category: 'reaction',
    description: 'Suspicious, sus',
    keywords: ['sus', 'suspicious', 'doubt'],
    intensity: 2
  },
  avalonTHINK: {
    name: 'avalonTHINK',
    category: 'neutral',
    description: 'Thinking, pondering',
    keywords: ['think', 'ponder', 'consider'],
    intensity: 1
  },
  avalonUH: {
    name: 'avalonUH',
    category: 'neutral',
    description: 'Hesitation, uh...',
    keywords: ['uh', 'hesitate', 'um'],
    intensity: 1
  },
  avalonUP: {
    name: 'avalonUP',
    category: 'positive',
    description: 'Thumbs up, approval',
    keywords: ['thumbs up', 'approve', 'good'],
    intensity: 2
  },
  avalonV: {
    name: 'avalonV',
    category: 'positive',
    description: 'Victory sign, V for victory',
    keywords: ['victory', 'peace', 'v sign'],
    intensity: 2
  },
  avalonW: {
    name: 'avalonW',
    category: 'positive',
    description: 'Win, W for win',
    keywords: ['win', 'victory', 'success'],
    intensity: 2
  },
  avalonWAAH: {
    name: 'avalonWAAH',
    category: 'meme',
    description: 'Lalafell /surprise emote from FFXIV',
    keywords: ['ffxiv', 'lalafell', 'surprise', 'waah'],
    intensity: 2
  },
  avalonWAVE: {
    name: 'avalonWAVE',
    category: 'action',
    description: 'Waving hello or goodbye',
    keywords: ['wave', 'hello', 'goodbye'],
    intensity: 1
  },
  avalonWHATISTHIS: {
    name: 'avalonWHATISTHIS',
    category: 'hype',
    description: 'Shaking in excitement, superhype',
    keywords: ['excited', 'shaking', 'incredible', 'amazing'],
    intensity: 3
  },
  avalonWHEE: {
    name: 'avalonWHEE',
    category: 'hype',
    description: 'Whee! Fun excitement',
    keywords: ['whee', 'fun', 'excited'],
    intensity: 2
  },
  avalonWHY: {
    name: 'avalonWHY',
    category: 'negative',
    description: 'I hate my life, existential dread',
    keywords: ['hate my life', 'why me', 'suffering'],
    intensity: 3
  },
  avalonWIGGLE: {
    name: 'avalonWIGGLE',
    category: 'action',
    description: 'Wiggling, cute movement',
    keywords: ['wiggle', 'dance', 'cute'],
    intensity: 2
  },
  avalonWOW: {
    name: 'avalonWOW',
    category: 'hype',
    description: 'Wow, impressed, amazed',
    keywords: ['wow', 'impressed', 'amazing'],
    intensity: 3
  },
  avalonWUT: {
    name: 'avalonWUT',
    category: 'neutral',
    description: 'What, confused',
    keywords: ['what', 'wut', 'confused'],
    intensity: 1
  },
  avalonYEP: {
    name: 'avalonYEP',
    category: 'positive',
    description: 'Yes, agreement, yep',
    keywords: ['yes', 'yep', 'agree'],
    intensity: 1
  },
  avalonYIKES: {
    name: 'avalonYIKES',
    category: 'negative',
    description: 'Yikes, bad situation',
    keywords: ['yikes', 'bad', 'terrible'],
    intensity: 2
  },
  avalonYUM: {
    name: 'avalonYUM',
    category: 'positive',
    description: 'Delicious, tasty, yum',
    keywords: ['yum', 'delicious', 'tasty'],
    intensity: 2
  }
}

export class AvalonstarEmoteRepository {
  getAllEmotes(): string[] {
    return Object.keys(AVALONSTAR_EMOTES)
  }

  getEmoteMapping(name: string): EmoteMapping | undefined {
    return AVALONSTAR_EMOTES[name]
  }

  hasEmote(name: string): boolean {
    return name in AVALONSTAR_EMOTES
  }

  /**
   * Match emotes based on keywords in transcribed text
   */
  matchEmotesToText(text: string): EmoteMapping[] {
    const lowerText = text.toLowerCase()
    const matches: EmoteMapping[] = []

    for (const emote of Object.values(AVALONSTAR_EMOTES)) {
      const hasMatch = emote.keywords.some((keyword) => lowerText.includes(keyword.toLowerCase()))
      if (hasMatch) {
        matches.push(emote)
      }
    }

    return matches
  }

  /**
   * Filter AI suggested emotes to only include available channel emotes
   */
  filterAvailableEmotes(suggestions: string[]): string[] {
    return suggestions.filter((name) => this.hasEmote(name))
  }

  /**
   * Select emotes based on emotion and intensity
   */
  selectEmotesForEmotion(emotion: EmoteAnalysis['emotion'], intensity: number): string[] {
    let category: EmoteMapping['category']

    switch (emotion) {
      case 'excited':
      case 'hype':
        category = 'hype'
        break
      case 'happy':
        category = 'positive'
        break
      case 'frustrated':
      case 'sad':
        category = 'negative'
        break
      case 'confused':
      case 'thinking':
      case 'neutral':
        category = 'neutral'
        break
      default:
        category = 'reaction'
    }

    const categoryEmotes = Object.values(AVALONSTAR_EMOTES).filter((emote) => emote.category === category)

    // Filter by intensity (higher AI intensity = higher emote intensity)
    const targetIntensity = intensity >= 7 ? 3 : intensity >= 4 ? 2 : 1
    const filteredEmotes = categoryEmotes.filter((emote) => emote.intensity <= targetIntensity)

    // Return emote names, or fallback to some channel emotes if no matches
    if (filteredEmotes.length > 0) {
      return filteredEmotes.map((emote) => emote.name)
    }

    // Fallback: return a few channel emotes based on basic emotion
    return this.getFallbackEmotes(emotion).slice(0, 3)
  }

  /**
   * Fallback emote selection for emotions
   */
  private getFallbackEmotes(emotion: EmoteAnalysis['emotion']): string[] {
    switch (emotion) {
      case 'excited':
      case 'hype':
        return ['avalonHYPE', 'avalonWOW', 'avalonWHATISTHIS']
      case 'happy':
        return ['avalonHAPPY', 'avalonUP', 'avalonYEP']
      case 'frustrated':
        return ['avalonRAGE', 'avalonWHY', 'avalonSTRESS']
      case 'sad':
        return ['avalonCRY', 'avalonWAAH', 'avalonOOF']
      case 'confused':
        return ['avalonHUH', 'avalonWUT', 'avalonTHINK']
      case 'thinking':
        return ['avalonTHINK', 'avalonHUH']
      default:
        return ['avalonSHRUG', 'avalonFINE', 'avalonNOD']
    }
  }
}

// Export singleton instance
export const avalonstarEmoteRepository = new AvalonstarEmoteRepository()

import { describe, test, expect } from 'bun:test'
import { AvalonstarEmoteRepository, avalonstarEmoteRepository, AVALONSTAR_EMOTES, type EmoteAnalysis } from '../emotes'

describe('AvalonstarEmoteRepository', () => {
  const repository = new AvalonstarEmoteRepository()

  describe('Basic Operations', () => {
    test('getAllEmotes returns all emote names', () => {
      const emotes = repository.getAllEmotes()
      const expectedEmotes = Object.keys(AVALONSTAR_EMOTES)

      expect(emotes).toEqual(expectedEmotes)
      expect(emotes.length).toBeGreaterThan(100) // We know there are 102 emotes
    })

    test('getEmoteMapping returns correct mapping for valid emote', () => {
      const mapping = repository.getEmoteMapping('avalonHYPE')

      expect(mapping).toBeDefined()
      expect(mapping?.name).toBe('avalonHYPE')
      expect(mapping?.category).toBe('hype')
      expect(mapping?.keywords).toContain('hype')
    })

    test('getEmoteMapping returns undefined for invalid emote', () => {
      const mapping = repository.getEmoteMapping('nonexistentEmote')

      expect(mapping).toBeUndefined()
    })

    test('hasEmote correctly identifies existing emotes', () => {
      expect(repository.hasEmote('avalonHYPE')).toBe(true)
      expect(repository.hasEmote('avalonLOVE')).toBe(true)
      expect(repository.hasEmote('nonexistentEmote')).toBe(false)
    })
  })

  describe('Text Matching - Property-Based Testing', () => {
    test('matchEmotesToText is case-insensitive', () => {
      const testCases = ['HYPE TIME!', 'hype time!', 'Hype Time!', 'hYpE tImE!']

      const results = testCases.map((text) => repository.matchEmotesToText(text))

      // All results should be identical
      results.forEach((result) => {
        expect(result.length).toBeGreaterThan(0)
        expect(result[0].name).toBe('avalonHYPE')
      })
    })

    test('matchEmotesToText handles empty and whitespace-only text', () => {
      expect(repository.matchEmotesToText('')).toEqual([])
      expect(repository.matchEmotesToText('   ')).toEqual([])
      expect(repository.matchEmotesToText('\n\t')).toEqual([])
    })

    test('matchEmotesToText finds multiple matching emotes', () => {
      const text = "I'm so happy and excited, feeling blessed!"
      const matches = repository.matchEmotesToText(text)

      expect(matches.length).toBeGreaterThan(1)

      const emoteNames = matches.map((m) => m.name)
      expect(emoteNames).toContain('avalonHAPPY')
      expect(emoteNames).toContain('avalonBLESS')
    })

    test('matchEmotesToText handles special characters and punctuation', () => {
      const text = "Wow!!! This is amazing... I'm so excited!!!"
      const matches = repository.matchEmotesToText(text)

      expect(matches.length).toBeGreaterThan(0)
      expect(
        matches.some((m) => m.keywords.some((k) => "wow!!! this is amazing... i'm so excited!!!".includes(k)))
      ).toBe(true)
    })

    test('matchEmotesToText consistency property', () => {
      const testTexts = [
        'happy time',
        'feeling sad today',
        'so confused about this',
        'hype hype hype',
        'yikes that was bad'
      ]

      testTexts.forEach((text) => {
        const result1 = repository.matchEmotesToText(text)
        const result2 = repository.matchEmotesToText(text)

        // Results should be identical for the same input
        expect(result1).toEqual(result2)
      })
    })
  })

  describe('Emote Filtering', () => {
    test('filterAvailableEmotes removes non-existent emotes', () => {
      const suggestions = [
        'avalonHYPE', // exists
        'fakeEmote1', // doesn't exist
        'avalonLOVE', // exists
        'anotherFake', // doesn't exist
        'avalonCRY' // exists
      ]

      const filtered = repository.filterAvailableEmotes(suggestions)

      expect(filtered).toEqual(['avalonHYPE', 'avalonLOVE', 'avalonCRY'])
    })

    test('filterAvailableEmotes handles empty array', () => {
      expect(repository.filterAvailableEmotes([])).toEqual([])
    })

    test('filterAvailableEmotes handles all invalid emotes', () => {
      const suggestions = ['fake1', 'fake2', 'fake3']

      expect(repository.filterAvailableEmotes(suggestions)).toEqual([])
    })
  })

  describe('Emotion-Based Selection', () => {
    test("selectEmotesForEmotion returns appropriate emotes for 'excited'", () => {
      const emotes = repository.selectEmotesForEmotion('excited', 8)

      expect(emotes.length).toBeGreaterThan(0)
      expect(emotes).toContain('avalonHYPE')
    })

    test("selectEmotesForEmotion returns appropriate emotes for 'sad'", () => {
      const emotes = repository.selectEmotesForEmotion('sad', 6)

      expect(emotes.length).toBeGreaterThan(0)
      expect(emotes).toContain('avalonCRY')
    })

    test('selectEmotesForEmotion handles intensity boundaries', () => {
      const emotions: EmoteAnalysis['emotion'][] = [
        'excited',
        'happy',
        'sad',
        'confused',
        'frustrated',
        'thinking',
        'neutral',
        'hype'
      ]
      const intensities = [0, 1, 3.5, 7, 10]

      emotions.forEach((emotion) => {
        intensities.forEach((intensity) => {
          const emotes = repository.selectEmotesForEmotion(emotion, intensity)

          // Should always return some emotes (fallback behavior)
          expect(emotes.length).toBeGreaterThan(0)

          // All returned emotes should exist in our repository
          emotes.forEach((emoteName) => {
            expect(repository.hasEmote(emoteName)).toBe(true)
          })
        })
      })
    })

    test('selectEmotesForEmotion intensity affects emote selection', () => {
      // High intensity should return high-intensity emotes
      const highIntensityEmotes = repository.selectEmotesForEmotion('excited', 10)
      const lowIntensityEmotes = repository.selectEmotesForEmotion('excited', 1)

      expect(highIntensityEmotes.length).toBeGreaterThan(0)
      expect(lowIntensityEmotes.length).toBeGreaterThan(0)

      // Should contain appropriate intensity emotes
      const highEmoteMappings = highIntensityEmotes.map((name) => repository.getEmoteMapping(name)).filter(Boolean)

      // High intensity selection should include high-intensity emotes
      expect(highEmoteMappings.some((mapping) => mapping!.intensity >= 2)).toBe(true)
    })

    test('selectEmotesForEmotion returns valid emote names', () => {
      const emotions: EmoteAnalysis['emotion'][] = ['excited', 'happy', 'sad', 'confused']

      emotions.forEach((emotion) => {
        const emotes = repository.selectEmotesForEmotion(emotion, 5)

        emotes.forEach((emoteName) => {
          // Each emote name should be a valid string
          expect(typeof emoteName).toBe('string')
          expect(emoteName.length).toBeGreaterThan(0)

          // Each emote should exist in our data
          expect(repository.hasEmote(emoteName)).toBe(true)
        })
      })
    })
  })

  describe('Singleton Instance', () => {
    test('avalonstarEmoteRepository is properly exported', () => {
      expect(avalonstarEmoteRepository).toBeInstanceOf(AvalonstarEmoteRepository)

      // Should behave the same as a new instance
      expect(avalonstarEmoteRepository.getAllEmotes()).toEqual(repository.getAllEmotes())
      expect(avalonstarEmoteRepository.hasEmote('avalonHYPE')).toBe(true)
    })
  })

  describe('Data Integrity', () => {
    test('all emotes have required properties', () => {
      Object.entries(AVALONSTAR_EMOTES).forEach(([name, mapping]) => {
        expect(mapping.name).toBe(name)
        expect(mapping.category).toMatch(/^(positive|negative|neutral|hype|reaction|action|meme)$/)
        expect(mapping.description).toBeTruthy()
        expect(Array.isArray(mapping.keywords)).toBe(true)
        expect(mapping.keywords.length).toBeGreaterThan(0)
        expect([1, 2, 3]).toContain(mapping.intensity)
      })
    })

    test('emote keywords are lowercase', () => {
      Object.values(AVALONSTAR_EMOTES).forEach((mapping) => {
        mapping.keywords.forEach((keyword) => {
          expect(keyword).toBe(keyword.toLowerCase())
        })
      })
    })

    test('no duplicate emote names', () => {
      const emoteNames = Object.keys(AVALONSTAR_EMOTES)
      const uniqueNames = new Set(emoteNames)

      expect(uniqueNames.size).toBe(emoteNames.length)
    })
  })
})

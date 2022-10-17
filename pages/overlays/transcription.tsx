import { NextPage } from 'next'
import { Fragment, useEffect, useRef, useState } from 'react'
import {
  useSpeechContext,
  SpeechSegment,
  Entity,
  Intent,
  Word
} from '@speechly/react-client'
import { useHasMounted } from '~/hooks'

const Transcription: NextPage = () => {
  const hasMounted = useHasMounted()
  const [textContent, setTextContent] = useState<string>('')
  const [tentativeTextContent, setTentativeTextContent] = useState<string>('')

  const {
    attachMicrophone,
    listening,
    segment,
    client,
    clientState,
    microphoneState
  } = useSpeechContext()

  const initMic = async (): Promise<void> => {
    await attachMicrophone()
  }

  useEffect(() => {
    hasMounted && initMic()
  }, [])

  const toSentenceCase = (str: string) => {
    const alphabet = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z'
    ]
    const punctuation = ['.', '!', '?']
    alphabet.forEach(letter => {
      punctuation.forEach(punc => {
        str = str.replace(
          `${punc} ${letter.toLowerCase()}`,
          `${punc} ${letter}`
        )
      })
    })
    return str.charAt(0).toUpperCase() + str.substr(1)
  }

  useEffect(() => {
    if (segment) {
      const plainString = segment.words
        .filter(w => w.value)
        .map(w => w.value)
        .join(' ')
      const casedTextContent = toSentenceCase(plainString)
    }
  }, [segment])

  // useEffect(() => {
  //   if (segment) {
  //     console.log(segment)

  //     if (segment.isFinal) {
  //       console.log('✅', segment)
  //     }
  //   }
  // }, [segment])

  return (
    <div>
      {segment ? (
        <div className="segment">
          {toSentenceCase(
            segment.words
              .filter(w => w.value)
              .map(w => w.value)
              .join(' ')
          )}
        </div>
      ) : null}
    </div>
  )
}

export default Transcription

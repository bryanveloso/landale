import { FC, useMemo, useState } from 'react'
import { differenceInHours, parseISO } from 'date-fns'

import Icon from '~/components/icons'
import { useStream } from '~/hooks'

export const Battery: FC = () => {
  const { data } = useStream()
  const [iconString, setIconString] = useState<string>('battery-full-line')
  const [iconColor, setIconColor] = useState<string>('text-green-400')

  useMemo(() => {
    if (data.startDate !== undefined) {
      const difference: number = differenceInHours(
        Date.now(),
        parseISO(data.startDate)
      )

      if (difference >= 4) {
        setIconString('battery-half-line')
      } else if (difference >= 6) {
        setIconString('battery-low-line')
        setIconColor('text-yellow-400')
      } else if (difference >= 8) {
        setIconString('battery-line')
        setIconColor('text-red-400')
      }
    }
  }, [data.startDate])

  return <Icon icon={iconString} size={24} className={iconColor} />
}

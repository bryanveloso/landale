import Image from 'next/image'
import { FC } from 'react'

import { Avalonstar } from './icons'

export const Logomark: FC = () => {
  return (
    <div className="flex gap-3">
      <Image
        src="/avalonstar.png"
        width={36}
        height={36}
        alt="Avocadostar"
        priority
      />
      <Avalonstar className="text-white w-40" />
    </div>
  )
}

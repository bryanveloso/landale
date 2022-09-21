import type { FC } from 'react'
import Clock from 'react-live-clock'
import Image from 'next/future/image'

import { Battery100Icon } from '~/components/icons'
import { useHasMounted } from '~/hooks'

import logo from '../../public/avalonstar.png'

export const MenuBar: FC = () => {
  const hasMounted = useHasMounted()

  return (
    <div className="absolute w-[1920px] h-12 px-6 flex items-center backdrop-blur-xl bg-black/25 text-system">
      <div className="flex justify-start gap-4">
        <Image src={logo} alt="Logo" className="w-6" />
        <div className="flex-auto font-bold text-white">Avalonstar</div>
      </div>
      <div className="flex-1 text-gray-100 text-right tabular-nums">
        <div className="flex justify-end gap-4">
          <Battery100Icon className="w-6 h-6 text-green-400" />
          {hasMounted && <Clock ticking format="MMM D h:mm A" />}
        </div>
      </div>
    </div>
  )
}

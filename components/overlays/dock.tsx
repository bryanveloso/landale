import { FC } from 'react'
import Image from 'next/image'

export const Dock: FC = () => {
  return (
    <div className="absolute bottom-0 w-full">
      <div className="flex mx-auto w-max gap-0 justify-center">
        <Image src="/dock/v.png" alt="Dock Icon" width={64} height={64} />
        <Image src="/dock/v.png" alt="Dock Icon" width={64} height={64} />
        <Image src="/dock/v.png" alt="Dock Icon" width={64} height={64} />
        <Image src="/dock/v.png" alt="Dock Icon" width={64} height={64} />
      </div>
    </div>
  )
}

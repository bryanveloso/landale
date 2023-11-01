import { Avalonstar } from '@/components/icons'
import { Rainwave } from '@/components/modules/rainwave'
import Image from 'next/image'

export default function () {
  return (
    <>
      <div className={`flex-auto`}></div>
      <div
        className={`h-24 flex items-end bg-gradient-to-b from-transparent to-[#000000bf]`}
      >
        <div className="flex items-center p-8">
          <div className="flex gap-3 pl-[1200px]">
            <Image
              src="avalonstar.png"
              width={36}
              height={36}
              alt="Avocadostar"
              priority
            />
            <Avalonstar className="text-white w-40" />

            <Rainwave />
          </div>
        </div>
      </div>
      <div
        className={`h-1 bg-gradient-to-br from-[#5be058] to-[#ffdd33]`}
      ></div>
    </>
  )
}

import Image from 'next/image'

import { Avalonstar } from '@/components/icons'
import { Rainwave } from '@/components/modules/rainwave'
import { Logomark } from '@/components/logomark'

export default function () {
  return (
    <>
      <div
        className={`flex-auto bg-gradient-to-b from-[#1a1f23] to-[#000]`}
      ></div>
      <div className={`h-24 bg-[#000] border-[#6644e8] border-b-2 px-6`}>
        <div className={`flex items-center h-full`}>
          <Logomark />
          {/* <Rainwave /> */}
        </div>
      </div>
    </>
  )
}

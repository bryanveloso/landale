import { useQuery } from '@tanstack/react-query'

import Image from 'next/future/image'
import { FC } from 'react'
import axios from 'redaxios'

const GenshinModule: FC = () => {
  // Fetch metadata information.
  const { data } = useQuery(['genshin'], async () => {
    return await (
      await axios.get('/api/games/genshin')
    ).data
  })

  if (!data) return <div>loading...</div>

  return (
    <div className="flex flex-col text-white p-4">
      <div className="flex">
        <Image
          src="https://upload-os-bbs.mihoyo.com/game_record/genshin/character_card_icon/UI_AvatarIcon_PlayerGirl_Card.png"
          alt="Traveler"
          width="256"
          height="256"
          className="w-1/2 -ml-4 -mt-12"
        />
        <div className="flex-auto leading-3">
          <span className="block text-xl font-bold">
            {data.data.role.nickname}
          </span>
          <span className="text-xs font-semibold text-white/80">
            Adventurer Level {data.data.role.level}
          </span>
        </div>
      </div>
      <div className="divide-y divide-white/30">
        <div className="py-2">
          Days Active: <strong>{data.data.stats.active_day_number}</strong>
        </div>
        <div className="py-2">
          Characters Collected: <strong>{data.data.stats.avatar_number}</strong>
        </div>
      </div>
    </div>
  )
}

export default GenshinModule

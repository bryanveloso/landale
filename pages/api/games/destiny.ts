import { NextApiRequest } from 'next'
import { Quria, BungieMembershipType, DestinyComponentType } from 'quria'

import { type NextApiResponseServerIO } from '~/lib'

export default async function handler(
  _req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const quria = new Quria({
    API_KEY: process.env.BUNGIE_API_KEY!,
    CLIENT_ID: process.env.BUNGIE_CLIENT_ID!
  })

  try {
    const response = await quria.destiny2.GetProfile(
      '4611686018467332261',
      BungieMembershipType.TigerSteam,
      {
        components: [
          DestinyComponentType.Profiles,
          DestinyComponentType.Characters,
          DestinyComponentType.CharacterEquipment
        ]
      }
    )

    res.status(200).json(response)
  } catch (error) {
    res.status(500)
  }
}

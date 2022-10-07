import { NextApiRequest } from 'next'

import { getChannelInfo, type NextApiResponseServerIO } from '~/lib'

export default async function handler(
  _req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const channel = await getChannelInfo(res)
  const payload = {
    delay: channel?.delay,
    displayName: channel?.displayName,
    gameId: channel?.gameId,
    gameName: channel?.gameName,
    id: channel?.id,
    language: channel?.language,
    name: channel?.name,
    title: channel?.title
  }

  res.status(200).json(payload)
}

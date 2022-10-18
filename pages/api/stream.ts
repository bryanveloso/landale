import type { NextApiRequest } from 'next'

import { getStreamInfo, NextApiResponseServerIO } from '~/lib'

export default async function handler(
  _req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const stream = await getStreamInfo(res)
  const payload = {
    gameId: stream?.gameId,
    gameName: stream?.gameName,
    id: stream?.id,
    isMature: stream?.isMature,
    language: stream?.language,
    startDate: stream?.startDate,
    tagIds: stream?.tagIds,
    thumbnailUrl: stream?.thumbnailUrl,
    title: stream?.title,
    type: stream?.type,
    userDisplayName: stream?.userDisplayName,
    userId: stream?.userId,
    userName: stream?.userName,
    viewers: stream?.viewers
  }

  res.status(200).json(payload)
}

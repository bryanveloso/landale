import type { NextApiRequest } from 'next'

import { getStreamInfo, NextApiResponseServerIO } from '~/lib'

export default async function handler(
  _req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const stream = await getStreamInfo(res)
  res.status(200).json(stream)
}

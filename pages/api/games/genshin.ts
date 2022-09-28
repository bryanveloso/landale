import crypto from 'crypto'
import axios from 'redaxios'
import { NextApiRequest } from 'next'
import { NextApiResponseServerIO } from '~/lib'

/**
 * Available Genshin API Endpoints:
 * - /index: General player information, pulled characters, etc.
 * - /dailyNote: Daily ritual information, resin count, etc.
 */

const apiUrl = 'https://bbs-api-os.hoyolab.com/game_record/genshin/api/index'
const cookie = process.env.GENSHIN_USER_COOKIE!!
const server = 'os_usa'
const uid = process.env.GENSHIN_USER_ID!!

function randomString(e: number) {
  const s = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
  const res = []
  for (let i = 0; i < e; ++i) {
    res.push(s[Math.floor(Math.random() * s.length)])
  }
  return res.join('')
}

const getDynamicSecret = (salt: string) => {
  const time = Math.floor(Date.now() / 1000)
  const random = randomString(6)

  const c = crypto
    .createHash('md5')
    .update(`salt=${salt}&t=${time}&r=${random}`)
    .digest('hex')
  return `${time},${random},${c}`
}

export default async function handler(
  _req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const ds = getDynamicSecret('6s25p5ox5y14umn1p61aqyyvbvvl3lrt')

  try {
    const { data } = await axios.get(apiUrl, {
      withCredentials: true,
      params: { role_id: uid, server },
      headers: {
        DS: ds,
        'x-rpc-language': 'en-us',
        'x-rpc-app_version': '1.5.0',
        'x-rpc-client_type': '5',
        Cookie: cookie
      }
    })

    res.status(200).json(data)
  } catch (error) {
    res.status(500)
  }
}

import crypto from 'crypto'
import { NextApiRequest } from 'next'
import { NextApiResponseServerIO } from '~/lib'
import { logger } from '~/logger'

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
  req: NextApiRequest,
  res: NextApiResponseServerIO
) {
  const url = `${apiUrl}?role_id=${uid}&server=${server}`
  const ds = getDynamicSecret('6s25p5ox5y14umn1p61aqyyvbvvl3lrt')

  console.log(ds)

  const response = await fetch(url, {
    method: 'GET',
    credentials: 'include',
    headers: {
      DS: ds,
      'x-rpc-language': 'en-us',
      'x-rpc-app_version': '1.5.0',
      'x-rpc-client_type': '5',
      Cookie: cookie
    }
  })

  if (!response.ok) {
    logger.error(`Fetch error: ${response.statusText}`)
  }

  const json = await response.json()

  res.status(200).json(json)
}

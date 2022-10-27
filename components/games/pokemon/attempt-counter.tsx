import { motion } from 'framer-motion'
import { useQuery } from '@tanstack/react-query'
import { FC } from 'react'
import axios from 'redaxios'

const AttemptCounter: FC = () => {
  const { data } = useQuery(
    ['kaizo'],
    async () => {
      return await (
        await axios.get('http://192.168.88.56:8008/stats/kaizo')
      ).data
    },
    { refetchInterval: 1000 * 10 }
  )

  return (
    <div>
      <motion.div
        layout="position"
        className="grow flex items-center gap-3 pr-3 bg-black/40 rounded-md"
      >
        <div className="bg-black/40 p-2 rounded-l-md px-3 font-semibold text-sm text-white/50">
          Number of Attempts
        </div>
        <div className="font-bold">{data && data.attempts}</div>
      </motion.div>
    </div>
  )
}

export default AttemptCounter

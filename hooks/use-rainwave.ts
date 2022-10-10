import axios from 'redaxios'
import { useQuery } from '@tanstack/react-query'

export const useRainwave = () => {
  const { data } = useQuery(['rainwave'], async () => {
    return await (
      await axios.get('https://rainwave.cc/api4/info', { params: { sid: 2 } })
    ).data
  })

  return { data }
}

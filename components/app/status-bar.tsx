import { useObs } from '~/landale/hooks'

export const StatusBar = () => {
  const { connected } = useObs()

  return <div connected={connected}> OBS Studio</div>
}

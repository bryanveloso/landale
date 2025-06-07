import { createFileRoute } from '@tanstack/react-router'
import FlyingToasters, {
  defaultToasterConfig,
  toast0Config,
  toast1Config,
  toast2Config,
  toast3Config
} from '@/components/flying-toasters'

export const Route = createFileRoute('/(full)/flying-toasters')({
  component: FlyingToastersRoute
})

function FlyingToastersRoute() {
  return (
    <FlyingToasters
      sprites={[defaultToasterConfig, toast0Config, toast1Config, toast2Config, toast3Config]}
      density={5}
    />
  )
}

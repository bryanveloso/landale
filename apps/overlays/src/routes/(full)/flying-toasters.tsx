import { createFileRoute } from '@tanstack/react-router'
import FlyingToasters, {
  defaultToasterConfig,
  toast0Config,
  toast1Config,
  toast2Config,
  toast3Config
} from '@/components/flying-toasters'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(full)/flying-toasters')({
  component: FlyingToastersRoute
})

function FlyingToastersRoute() {
  return (
    <ErrorBoundary>
      <FlyingToasters
        sprites={[defaultToasterConfig, toast0Config, toast1Config, toast2Config, toast3Config]}
        density={5}
      />
    </ErrorBoundary>
  )
}

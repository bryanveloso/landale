import FlyingToasters, { defaultToasterConfig, defaultToastConfig } from './flying-toasters'

// Example of how to add custom sprites while preserving original timing
const customBagelConfig = {
  name: 'bagel',
  src: '/sprites/flying-bagel.png',
  frameWidth: 48,
  frameHeight: 48,
  frameCount: 4,
  speeds: [10, 16, 24], // Use same speeds as original
  delays: [0, 4, 5, 8, 12, 16, 20] // Use same delays as original
}

const customCatConfig = {
  name: 'cat',
  src: '/sprites/flying-cat.png',
  frameWidth: 56,
  frameHeight: 40,
  frameCount: 6, // Different frame count is fine
  speeds: [14, 18, 22], // Slightly different speeds for variety
  delays: [0, 3, 7, 11, 15] // Different delay pattern
}

const FlyingToastersExample = () => {
  return (
    <FlyingToasters
      sprites={[defaultToasterConfig, defaultToastConfig, customBagelConfig, customCatConfig]}
      density={15} // Fewer objects for less chaos
    />
  )
}

export default FlyingToastersExample

import { VerticalCamera } from '~/components/overlays'

const Foreground = () => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[1888px] h-[952px] rounded-lg shadow-2xl shadow-black/50 ring-1 ring-black ring-offset-0`}
    >
      <div className="absolute w-full h-full rounded-lg ring-2 ring-offset-0 ring-inset ring-white/30 z-50"></div>
      <VerticalCamera className="absolute bottom-2 left-2 z-50" />
    </div>
  )
}

export default Foreground

/**
 * Browser source size should be 432x312.
 */
const HorizontalCamera = () => {
  return (
    <div className="flex flex-col w-[384px] m-6 bg-[#343434] shadow-black/50 shadow-xl rounded-xl ring-1 ring-offset-0 ring-inset ring-white/20">
      <div className="flex-auto p-2 text-sm text-white font-bold">Camera</div>
      <div className="aspect-video m-2 mt-0 bg-[#1E1E1E] rounded-lg"></div>
    </div>
  )
}

export default HorizontalCamera

export default function SubpageLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div className={`relative w-[1920px] h-[1080px] flex flex-col`}>
      {children}
    </div>
  )
}

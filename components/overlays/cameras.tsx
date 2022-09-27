import { FC, HTMLAttributes } from 'react'

interface CameraProps extends HTMLAttributes<'div'> {
  zIndex: 'background' | 'foreground'
}

export const VerticalCamera: FC<CameraProps> = ({
  className,
  zIndex = 'background'
}) => {
  const foreground = (
    <div
      className={`absolute w-[312px] h-[416px] rounded-lg ring-2 ring-offset-0 ring-inset ring-white/10 z-50 ${className}`}
    />
  )

  const background = (
    <div
      className={`absolute w-[312px] h-[416px] bg-[#282828] rounded-md shadow-2xl shadow-black ${className}`}
    />
  )
  return zIndex === 'background' ? background : foreground
}

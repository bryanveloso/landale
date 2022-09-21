import { FC, HTMLAttributes } from 'react'

export const VerticalCamera: FC<HTMLAttributes<'div'>> = ({ className }) => {
  return (
    <div
      className={`w-[312px] h-[416px] bg-red-900 rounded-md drop-shadow-2xl ${className}`}
    ></div>
  )
}

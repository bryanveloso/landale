import type { FC, HTMLAttributes } from 'react'

export const Battery100Icon: FC<HTMLAttributes<'div'>> = ({ className }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    className={className}
  >
    <g>
      <path
        d="M24,10.5a2,2,0,0,0-2-2H21v-1a2,2,0,0,0-2-2H2a2,2,0,0,0-2,2v9a2,2,0,0,0,2,2H19a2,2,0,0,0,2-2v-1h1a2,2,0,0,0,2-2Zm-2,2.75a.25.25,0,0,1-.25.25H20a1,1,0,0,0-1,1V16a.51.51,0,0,1-.5.5H2.5A.5.5,0,0,1,2,16V8a.5.5,0,0,1,.5-.5h16A.5.5,0,0,1,19,8V9.5a1,1,0,0,0,1,1h1.75a.25.25,0,0,1,.25.25Z"
        fill="currentColor"
      />
      <rect x={3} y={8.5} width={15} height={7} rx={0.5} fill="currentColor" />
    </g>
  </svg>
)

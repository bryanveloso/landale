import type { ComponentPropsWithoutRef, FC } from 'react'

export const Battery100Icon: FC<ComponentPropsWithoutRef<'svg'>> = ({
  className
}) => (
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

export const ButtonRefreshArrow: FC<ComponentPropsWithoutRef<'svg'>> = ({
  className
}) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    className={className}
  >
    <path
      d="M10.66,20.07a1.25,1.25,0,0,0-.5,2.45,11,11,0,0,0,2.2.23,10.75,10.75,0,1,0-10-6.65.24.24,0,0,1-.09.29l-1,.73a1,1,0,0,0-.39,1,1,1,0,0,0,.77.77l4,.85.21,0a1,1,0,0,0,.54-.16A1.05,1.05,0,0,0,6.83,19l.94-4.4a1,1,0,0,0-1.56-1l-1.37,1a.24.24,0,0,1-.22,0,.22.22,0,0,1-.16-.16,8.26,8.26,0,1,1,6.2,5.64Z"
      fill="currentColor"
    />
  </svg>
)

export const NavigationMenu: FC<ComponentPropsWithoutRef<'svg'>> = ({
  className
}) => {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      className={className}
    >
      <g>
        <rect
          x={0.5}
          y={2.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
        <rect
          x={0.5}
          y={10.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
        <rect
          x={0.5}
          y={18.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
      </g>
    </svg>
  )
}

export const VideoGamePC: FC<ComponentPropsWithoutRef<'svg'>> = ({
  className
}) => {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      className={className}
    >
      <g>
        <path
          d="M6,3.75H9a2,2,0,0,1,2,2v4.5a1,1,0,0,0,2,0V5.75a4,4,0,0,0-4-4H6a1,1,0,0,0,0,2Z"
          fill="currentColor"
        />
        <path
          d="M18.5,11.25a5.54,5.54,0,0,0-3.64,1.37.46.46,0,0,1-.33.13H9.47a.46.46,0,0,1-.33-.13,5.5,5.5,0,1,0,0,8.26.46.46,0,0,1,.33-.13h5.06a.46.46,0,0,1,.33.13,5.5,5.5,0,1,0,3.64-9.63Zm-11.25,6H6.5a.5.5,0,0,0-.5.5v.75a.75.75,0,0,1-1.5,0v-.75a.5.5,0,0,0-.5-.5H3.25a.75.75,0,0,1,0-1.5H4a.5.5,0,0,0,.5-.5V14.5a.75.75,0,0,1,1.5,0v.75a.5.5,0,0,0,.5.5h.75a.75.75,0,0,1,0,1.5Zm8.75.5a1,1,0,1,1,1-1A1,1,0,0,1,16,17.75Zm2.5,2.5a1,1,0,1,1,1-1A1,1,0,0,1,18.5,20.25Zm0-5a1,1,0,1,1,1-1A1,1,0,0,1,18.5,15.25Zm2.5,2.5a1,1,0,1,1,1-1A1,1,0,0,1,21,17.75Z"
          fill="currentColor"
        />
      </g>
    </svg>
  )
}

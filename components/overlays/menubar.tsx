import React, { useState, useEffect } from 'react'

export const MenuBar = () => {
  const [time, setTime] = useState(
    new Date().toLocaleString('en-us', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric'
    })
  )

  useEffect(() => {
    let secTimer = setInterval(() => {
      setTime(
        new Date().toLocaleString('en-us', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          hour: 'numeric',
          minute: 'numeric',
          second: 'numeric'
        })
      )
    }, 1000 * 60)

    return () => clearInterval(secTimer)
  }, [])

  return (
    <div className="absolute w-[1920px] h-[48px] px-6 flex items-center backdrop-blur-md bg-black/50 text-system">
      <div className="flex-auto font-bold text-white">Avalonstar</div>
      <div className="flex-1 text-gray-100 text-right">{time}</div>
    </div>
  )
}

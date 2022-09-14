import { useEffect, useRef, useState } from 'react'

import { useSocket } from '@landale/hooks/use-socket'
import { getLayout } from '@landale/layouts/for-overlay'
import { useSocketEvent } from '@landale/hooks/use-socket-event'

export default function Notifier() {
  const { socket, connected } = useSocket()
  useSocketEvent(socket, 'notification', e => {
    console.log(e)
  })

  return (
    <div>
      <p>Connected: {'' + connected}</p>
    </div>
  )
}

Notifier.getLayout = getLayout

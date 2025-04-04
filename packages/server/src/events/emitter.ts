import Emittery from 'emittery'

import type { EventMap } from '@/events/types'

export const eventEmitter = new Emittery<EventMap>()

import axios from 'redaxios';
import type { RainwaveResponseTypes } from 'rainwave-websocket-sdk';

export const queryRainwave = async (): Promise<RainwaveResponseTypes> => {
  return (
    await axios.get<RainwaveResponseTypes>('https://rainwave.cc/api4/info', {
      params: {
        sid: 1,
        user_id: process.env.NEXT_PUBLIC_RAINWAVE_USER_ID,
        key: process.env.NEXT_PUBLIC_RAINWAVE_KEY,
      },
    })
  ).data;
};

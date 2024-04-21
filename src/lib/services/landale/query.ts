import axios from 'redaxios';

export type KaizoAttemptsResponse = { attempts: string };

export const queryAttempts = async (): Promise<KaizoAttemptsResponse> => {
  return (await axios.get('http://alys.veloso.house/stats/kaizo')).data;
};

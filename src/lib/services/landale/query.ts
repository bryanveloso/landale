import axios from 'redaxios';

export type KaizoAttemptsResponse = { attempts: string };

export const queryAttemptCount = async (): Promise<KaizoAttemptsResponse> => {
  return (await axios.get('http://alys.veloso.house/stats/kaizo')).data;
};

export const queryAttempts = async () => {
  return (await axios.get('http://alys.veloso.house/stats/kaizo/csv')).data;
};

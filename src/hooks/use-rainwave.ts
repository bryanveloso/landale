'use client'

import { useQuery } from '@tanstack/react-query';
import { queryRainwave } from '@/lib/services/rainwave/query';

export const useRainwave = () => {
  const { data, status } = useQuery({
    queryKey: ['rainwave'],
    queryFn: queryRainwave,
    refetchInterval: 10000,
    refetchIntervalInBackground: true,
  });

  return {
    data,
    isTunedIn: data?.user.tuned_in,
    status,
    song: data?.sched_current.songs[0],
  };
};

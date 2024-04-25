'use client';

import { useQuery } from '@tanstack/react-query';

import { queryAttemptCount, queryAttempts } from '@/lib/services/landale/query';

export const useKaizoAttemptCount = () => {
  const { data, status } = useQuery({
    queryKey: ['kaizo-attempt-count'],
    queryFn: queryAttemptCount,
    refetchInterval: 10000,
    refetchIntervalInBackground: true,
  });

  return {
    count: data?.attempts,
    status,
  };
};

export const useKaizoAttempts = () => {
  const { data, status } = useQuery({
    queryKey: ['kaizo-attempts'],
    queryFn: queryAttempts,
    refetchInterval: 10000,
    refetchIntervalInBackground: true,
  });

  return {
    csv: data,
    status,
  };
};

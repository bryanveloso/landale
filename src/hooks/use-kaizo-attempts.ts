'use client';

import { useQuery } from '@tanstack/react-query';
import { queryAttempts } from '@/lib/services/landale/query';

export const useKaizoAttempts = () => {
  const { data, status } = useQuery({
    queryKey: ['kaizo'],
    queryFn: queryAttempts,
    refetchInterval: 10000,
    refetchIntervalInBackground: true,
  });

  return {
    data,
    status,
  };
};

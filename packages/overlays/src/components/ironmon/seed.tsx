import { type FC } from 'react';
import { useQuery } from '@tanstack/react-query';

import { type SeedMessage } from '@/lib/services/ironmon';

export const Seed: FC = () => {
  const query = useQuery<SeedMessage['metadata']>({
    queryKey: ['ironmon', 'seed'],
    placeholderData: { count: 0 },

    // Because we recieve this data via a websocket, we don't want to refetch it.
    gcTime: Infinity,
    staleTime: Infinity,
    refetchOnMount: false,
  });

  return <div>{query.data?.count}</div>;
};
